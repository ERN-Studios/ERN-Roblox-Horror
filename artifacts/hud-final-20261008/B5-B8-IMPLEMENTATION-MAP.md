# B5-B8 implementation map

Prepared 2026-10-09 from the approved `OWNER-PICKS.md`, the current `BUILD-PLAN.md` including its Framewisp adaptation, `FRAMEWISP-PIPELINE.md`, real dumps under `tools/tests/fixtures/hud/`, and the mirrored production sources. This is an implementation map, not proof that these batches have been installed. No Studio, lock, git or production-file action was taken to prepare it.

Line references below describe the baseline read during this audit; other HUD workers can move them. Re-read the named function before applying a hunk. The coordinator must perform the live Studio baseline audit and merge any drift before a push.

## Ownership and order

| Owner | Exclusive files / responsibility | Handover dependency |
|---|---|---|
| Shared HUD owner | `RoundHud`: B4 ObjectiveCard/LastObjective and template utilities, then B5 Feed/Caption. `Round HUD`: B5 event listeners, Clear on round exit. Own shared harness and API tests. | Define API before downstream callers land. Preserve B3 mounted marker and stamina. |
| B5 caller owner | Level2AlertClient, Level 3 Reader Client toast block, Level 4 Round Client say/caption block, TeamObjectives copy callers, GameManager appended death count. | Wait for B4 reader/L4 ownership handover. Do not concurrently change their objective or note blocks. |
| B6 owner | Found Footage HUD, Round Exit Client, spectator-counter removal; GameManager RoundStartedAt if needed. | B5 GameManager handover first. SpectateController handed to B8 after removal. |
| B7 owner | Level 3 Table Hiding Client; Level 4 Round Client note/keypad/device layout. | Receive B4/B5 Level 4 source. Maintain objective Order-line reopen seam. |
| B8 owner | **All RoundUI changes in one owner:** loading, results/completion, PARTY DOWN, death do-block. SpectateController restyle. | Receive B4/B5 RoundUI edits and B6 SpectateController. Needs Stack/Paint/LastObjective/Keycap. |
| Coordinator | UIRegression path changes, manifest/new-script/delete handling, whole-place compile, scoped CAS push and Studio Play QA. | No bulk overwrite. New publish needs all shared unpublished changes understood. |

B5 and B6 can prepare offline work in separate files, but GameManager, RoundUI, Level 4 Round Client and SpectateController must each have a single current owner. The inherited build plan's imperative build-in-code sections are superseded by its final Framewisp adaptation: all authored visual parts are cloned from existing templates.

## Real template evidence and shared API demands

The real `framewisp-dump.HUD_Screens.json` has 1002 nodes, 237 fixed-size texts, no scripts, zero distinct images and 21 screen roots. Use it, not `artifacts/.../fixtures/framewisp-dump.HUD_Screens.SYNTHETIC.json`, for new tests. `HUD_PC` and `HUD_Touch` real fixtures also contain all B5/B6 roots.

`RoundHud` baseline already has `Gui`, `Bundle`, `Template`, `Mount`, `Attention`, `Keycap`, `Detector`, `Clear`. Later work needs the following **exported** contracts (private helpers are insufficient):

| API | Contract required downstream |
|---|---|
| `Stack(bundle,path,parent,opts) -> container,parts` | Mount each direct GuiObject child through `Mount` in authored Y order. Clone root look. Vertical auto-height; invisible Advice/party rows close gaps. `parts.Head`, `.Advice`, `.Footer`, `.PartyChoice1` etc. remain accessible. Each mounted part receives B3 Fill anchor treatment. |
| `Paint(root,templateName,level)` | Accent paths only: Loading Eyebrow/Underbar/Status Track Fill/current LevelTrack slot; Results Head Eyebrow; Objective paths per pipeline. Other loading slots and Status stay Sage. |
| `Ring(slot) -> set(fraction,colour)` | Code-drawn sweep for prompt/leave ring; no uploads. Clamp fraction; cancel/reset cleanly. |
| `Soften(node)` | Deterministic soft-Ink alpha, used by Mount/Stack and callers when necessary. |
| `SetObjective(state)`, `LastObjective()` | B8 loss counter uses last valid objective even after the in-round HUD hides. Preserve a snapshot until results read it; decide explicit reset timing, not an accidental `Clear` wipe. State must expose level, counter label/current/max, and Order-line activation callback where applicable. |
| `Feed(row)` | `{Kind, Actor/Who, Detail, Key?}`; accept a Player/name/id through a documented actor seam. Two PC rows, one touch; 4 s lifetime; same Key merges within 2 s. Resolves DisplayName, not @username. Mount rows once; events rewrite them. |
| `Caption(speaker,text)` | 3.5 s lifetime; gated by CaptionsEnabled and not DisableCaptions. Same eligibility as source event before call. Touch uses feed lane; PC sits above marker. |
| `Clear()` | Teardown only module-owned Objective/Detector/Feed/Caption nodes. Never destroy caller-owned B3 marker/stamina. Do not erase loss snapshot before results. |

Mount initially measures design size before removing the Scale chain, uses existing ShopBinder, sets actual touch text floor 12, and does not recreate icons. Device changes remount/rebind the alternate template while preserving view state and disconnecting old signal connections. Use `Binder.at` segment searches: actual imports insert `Items` wrappers.

## B5: event feed and captions

Template nodes are `HUD_PC/FeedRow`, `Caption`, `HUD_Touch/FeedRowTouch`, `CaptionTouch`. Feed paths: `Soft`, `Bar`, `Dot`, `Initial/Ring`, `Initial/Letter`, `Words/Who`, `Words/Detail`; `Binder.flowRow(Words)` keeps detail after measured name. Bar = RailTeal TEAM, Coral DANGER, Cream SYSTEM; LEVEL hides Bar and shows Amber Dot. Caption paths = `Soft`, `Speaker`, `Said`.

Preserve the data/event gates while replacing drawing:

- `Team Objective Feed` has level equality, InRound, monotonic payload.Serial, Actor/Detail type checks. Move these into Round HUD before retiring the script/GUI and manifest entry. No new server-authoritative progress is computed client-side.
- GameManager `hookLife` currently fires `fireGroup(participants, "death", player.Name, position, lastDeathCause)` at line 2794. Append `aliveCount` **after** the cause; the client callback receives kind/name/position/cause/count. Existing own-death explanation, kill timing, and spectate payload order stay intact. It is append-only, not a new remote.
- Round HUD adds objective/death/escape listeners. Use DisplayName lookup (retain a safe text fallback when actor left), suppress local escape feed if own results already shows it, and avoid duplicating RoundUI's teammate escape status at lines 4656 onward.
- Actual Level 2 filename is **`Level2AlertClient.LocalScript.lua`**, not the spaced name in some prose. Replace `presentAlert` (line 550) draw work with feed delivery; keep `announcementAllowed`, event connection, dedupe and valve ESP. Retire `Level2AlertOwnsBand` only with B4's objective caller change, so an obsolete alert flag cannot suppress the new card.
- Reader `showToast` (line 899) retains sanitisation/server event handling; replace toast drawing and the hidden-under-table drop. Remove toast.Visible conditions that only served collision with the retired panel. Do not change Energon/device/signal/audio logic.
- Level 4 `say` (line 133) becomes LEVEL feed. Event `Shush` (line 971) calls `Caption("USHER","Shhh...")` while retaining current nearby/self eligibility; drop bracketed quote copy. `CaptionsEnabled` and `DisableCaptions` gates remain effective. Cinematic title, lighting, film and Usher interpolation are outside this restyle.
- TeamObjectives callers are `Level 1 Systems/PuzzleManager.Script.lua`, Level 2 Objective Controller line 570, Level 3 Objective Controller lines 655/1004. Copy changes only; leave serial/state/progress. Dormant Level 6 preview callers stay untouched.

Deduplication requires a common key on pump/CD announcements and local alerts. Establish keys at the caller seam; a merge implementation alone cannot collapse events if callers pass different keys. If an old alert carries no actor/key, only combine it with a team row when source state proves the same event; do not merge unrelated repeated breaker warnings globally.

Placement: safe top-centre; touch x=115..473 in reference 844x390, at least 12 px. Level3_Hiding moves feed below the banner rather than hiding it. Modal, result/loading and outside-round gates must prevent stale rows drawing behind screens. A caption replaces/reuses the touch feed lane rather than overlapping the live row.

## B6: REC, prompts and leave

### Found Footage HUD

The baseline file is now mirrored. `FoundFootageFrame` DisplayOrder is 4 (line 33), `Rec`/`Timecode` are code-created, and `roundStarted` is client-local (line 79). Its prompt builder starts line 150. It uppercases ObjectText/ActionText on show already; the old plate is radius 5 and owns hold halves/PromptButtonHold events.

- Mount `HUD_PC/RecLine`, `Bracket` four times; set GUI order 12. Actual REC slots: `Dot`, `Rec`, `Time`, `SignalLabel`, `Bars/Bar1..4`, `Watching`. Format elapsed mm:ss, h:mm:ss after an hour. Static bars, no blink. PC/pad only; all five roots hidden on touch, while prompts remain.
- Two GameManager RoundActive=true sites are lines 3121 and 3157; no `RoundStartedAt` exists in baseline. Add server-time attribute beside both writes to make two clients match; do not make it an independently advancing client timer. Preserve preview handling rather than assuming every RoundActive represents a normal routed round.
- Mount one pooled plate per currently shown prompt: PC `PromptPlate` or touch `PromptPlateTouch`. Actual PC paths are `Plate`, `KeyChip`, `RingSlot`, `ObjectLine`, `ActionLine`, `Reason`; touch `Plate` is a TextButton, plus `HoldBar/Track/Fill` and no keycap.
- Keep BillboardGui attachment, hold begin/end/trigger semantics, prompt adoption Custom style, connections and clean hide. Keycap receives actual keyboard/gamepad code. Render optional `HudDisabledReason` without changing server prompt Enabled or adding prompt wiring in this batch.
- Luna currently changes ActionText after show; preserve existing shown-copy behaviour where required and verify its Rub belly interaction. Do not indiscriminately reconnect ActionText in a way that reverses the prior fix.
- B6 removes SpectateController's code-created `SpectatorCounter` and calls (baseline 313..339, calls in start/stop/bindCharacter). REC reads own replicated SpectatorCount, visible only >0. Camera logic remains unchanged.

### Round Exit Client

Mount `HUD_PC/LeaveChip`, `LeaveChipWide`, `RoundExitNotice`, `RoundExitCard`; touch `HUD_Touch/LeaveChipTouch`. Actual confirm buttons are `BackToLobby` and `Stay`, with nested `Label`; name mounted card `RoundExitCard`. Expanded leave paths include `KeyChip`, `HoldFill`, `HoldHint`; notice path `Notice`; touch ring `RingSlot`.

Replace the old objective-obstacle avoidance list with the approved fixed safe top-left lane. PC 40x40 rest/240x40 expanded; touch 44x44 at safe-left+12/safe-top+6 (59,64 in reference), never expands. Keep click/hold/cancel, 1.5-second clock, leaveack/leavefailed pending handling, retry, RoundExitPromptOpen, and bindable RoundExitPrompt. Add View/Select hold; confirm defaults STAY and B=STAY. Dead/escaped spectate BackToLobby still uses the existing request route, not a second leave protocol.

## B7: table and cinema specials

### Level 3 hiding

Keep animation/joint/camera-clipping code, shade and letterbox. Existing state lives in the Level 3 state object, not solely player attributes: `Level3_MallManagerTableCheckIndex` and EndsAt at lines 414/418, and tableCheckWarned supplies table ownership.

Mount `HUD_Screens/HidingBanner`, `LeaveHiding`, `TableCheck` or `*Touch`; mounted names remain `HiddenStatus` where UIRegression requires it or update that row together. Paths = Banner; Leave KeyChip/Label; TableCheck Warn/Seconds/Track/Fill. Warn countdown uses server EndsAt and correct table index; capture start/deadline to derive fraction, clamp to zero. Banner rests 45%, leave 55% after 6s; table check forced bright. Current E/ButtonB/ButtonX requestExit paths remain. Touch leaves a 200x44 button and banner clear of door lane.

### Level 4 note/keypad

Receive B4/B5 source first. Preserve code-entry value, KeypadSubmit payload, remote kinds, auto-close beyond 10 studs, cursor restoration, sync and Usher logic. GUI order changes 6 to 60. Actual imported paths differ from the prose table:

- Note is root TextButton `Level4Note`; text = **`Body/Items/BodyLine1..4`**. Assign PatrickHand on each actual text. `CloseHint/KeyChip`, `CloseHint/Label`, `TapToClose`. No added X. Tap root closes on touch; E/B close. Reopen N/D-pad up and B4 Order-line callback; known Level4_NoteOrder required and do not reopen over another modal/keypad.
- Keypad `Display` is **`DisplayBox/Display`**. Keys are stripped names `Key1`..`Key9`, `KeyC`, `Key0`, `KeyOK`, each Label; close is `Close/Cross`. Status WRONG CODE, not old display DENY. Hints = PressHint/KeyChip + Label and CloseHint equivalents.
- Use the authored three-column ordering 1,2,3 /4,5,6 /7,8,9 /C,0,OK for NextSelection directions and wrap. Default focus on first usable key; A activates, B closes, Roblox MenuIsOpen passes. Preserve keyboard typing/chat guards.
- Keep existing UIDevice safe fit and touch-only Level4CardOpen publication (baseline 738..752), and remove B3 temporary gates only after order 60 protects overlays. Note PC 380x270/touch approximately340x240; keypad PC240x330/touch300 high. Re-fit labels after assigning PatrickHand rather than leaving Montserrat em sizing unchanged.

## B8: one register-safe RoundUI owner

`RoundUI` is a large shared chunk at the Luau register ceiling. No new top-level local is necessary: add helpers/refs to existing `completion`, `entryState`, `pd`, `dc` tables, or use do-block locals closed over by their callbacks. Load RoundHud/ShopBinder in the needed do-block, FindFirstChild+pcall as the current death block does, and fail by named warning rather than yielding the remainder of this script indefinitely. Compile the whole file after each subchange, not only extracted test blocks.

### Death card: implement first, isolate lifecycle from drawing

Existing own-death listener is at 5364; `copyFor` starts 5199; `dc` 5215; show/hide/layout 5297..5376. Keep copyFor fallback, own-name gate, serial/dwell=12, character/reset/reentry events and Studio DevDeathCause seam.

1. Mount `Stack HUD_Screens/DeathCause` or DeathCauseTouch and separate `DeathCauseDocked`/Touch. Bind Head/DeathCauseTitle, Cause/DeathCauseBody, Advice/DeathCauseEyebrow + Tip, Head/Close; dock Title/Close. Both close hits >=44x44.
2. Add `dc.closed` and stable advice snapshot; `dc.show` starts a fresh death serial, clears closed, renders both title slots, hides Advice when no tip and shows exactly one presentation. `dc.close` marks closed and increments serial; hide both roots. A scheduled dwell belongs to captured serial.
3. PartyDownCardOpen true switches to title-only **44-high dock always**, safe top-centre (PC74/touch64), above overlay ZIndex118. Replace the old viewport<620/overlapsModal heuristic and old title+tip compact design. Normal stack is Z96. Do not show either root in layout if dc.closed or no active death. Attribute/deferred layout callback may reposition existing shown content; it must not resurrect it.
4. Normal X and dock X share close; B action High sinks only when an active normal card is visible, PartyDownCardOpen is false, Roblox menu shut and input is Begin. Otherwise Pass. Do not steal B from PARTY DOWN decline or dispatch-stop. Dock X stays mouse/touch active under PARTY DOWN.
5. Esc closes on unprocessed InputBegan **and MenuOpened fallback**; truthful Esc keycap remains even if Roblox consumes the key. Touch has no hint. B glyph through Keycap. Close persists for this death; new death resets it.
6. Keep automatic 12s close; current delay defers while PARTY DOWN is open. Preserve that extension unless deliberately changing it; user approval specifically kept 12s auto-close, not removal. Reentry/start/lobby/loading/win/lose/CharacterAdded invalidates timers.
7. Device remount rebinds content and listeners from cached advice without calling show (which would wrongly reopen/reset dwell). Preserve closed state and serial.

### PARTY DOWN

Keep `PartyDownOverlay` code root and pd show/hide/refresh/arm/deadline/reentry/dev handling (baseline 4970..5161). Mount `PartyDownCard`/Touch; four brackets PC only. Actual buttons live under **`Offer/Items`** with nested Labels. TitleRow/PartyDownTitle + Timer; Track/PartyDownFill; Fallen; Reentry.

Full overlay navy black around4,7,16 at0.1; killcam order1000 remains above gui100. Preserve PartyDownWindowOpen after NO THANKS; only PartyDownCardOpen clears. This keeps legacy reentry modal suppressed and countdown running. Use DisplayName faller; nil faller hides line. Ineligible hides Reentry and purchase/free buttons as appropriate; Offer list closes gaps. Keep 0.6s arming and end-of-window standdown/backstop. Focus primary usable button after armed, fallback decline; B routes decline only while party card visible/menu shut.

Purchase caption states are Label.Text, not button.Text: USE CREDIT · n OWNED, BUY · R$ n · 0 OWNED, WAITING FOR ROBLOX..., developer DEV chip. Current pd has no explicit purchase-prompt pending state: add bounded latch cleared by PromptProductPurchaseFinished/profile attributes, without inventing a grant. Stored UseReentry still goes through the existing action. pd.refresh must never reset a waiting caption prematurely. Declined status goes to top-centre under feed, PARTY DOWN · n s, not old seconds-left/bullet line.

### Results / completion

Preserve completion Serial/Revision/member snapshot/deadline validation, Closed terminal state, per-action attrs, rate guard, continues/return errors and server request semantics. Baseline completion.applyChoices 1494, applyLayout1553, start1708, activate1743, countdown1774; show/hideRoundEnding1856/1876. Mount Stack Results/Touch into original RoundEnding; SignalFlash/SignalLine remain code-owned. On touch imported sheet726x293 fits safe area, >=44 targets; do not use old fixed fractions per label.

- Results stat Frame is Head/EndingStats/**Items**/Stat_Time, Stat_Survivors, Stat_Counter, each Label/Num. It replaces old TextLabel endStats; update every `.Text`, text tween, UIRegression read and test seam. Prefer structured data fields for time/survivors/level at caller instead of parsing formatted display strings. Loss counter uses LastObjective; hide if missing rather than fabricate.
- Actual PartyChoice1..6 rows are top-level stack parts. Reparent into code-made PartyChoices list only if needed without duplicating stack/layout ownership; retain fixed templates and hide unused rows. Fill Who/Initial/Letter/Sub/Chip/Label. Server snapshot currently carries UserId, Name, Choice only; resolve DisplayName by id. Do not enumerate all Players as party members. For loss/own escape before postwin snapshot, only use known round membership or an explicitly scoped roster seam; avoid presenting lobby players as party.
- Buttons are Footer/ContinueRun and ReturnToLobby with nested Label; set CompletionAction and connect existing activate. All returnpending/continuefailed/returnfailed text writes must target Label. Pressed text uses existing CompletionPressedText; change only when accepted pending travel state, not optimistically on first click if server permits changing choice.
- Countdown has Footer/Countdown and CountNum (flowRow); own escape title YOU GOT OUT, hint WAITING FOR THE OTHERS, then WATCHING <DisplayName> IN n. Win/loss titles retain preview-specific level resolution already in current win event (5/6/new2 flags); do not restore obsolete MaxLevel=4 assumptions.
- Gate SignalFlash on ReduceFlashing including DevRoundEnding test modes; keep sound and line behaviour. Align cleanup with HUD Clear without losing LastObjective before the loss card reads it.

### Loading

Baseline LOADING_PALETTES already contains owner colours1..6 and pure black, and entryState already holds mystery-title fields. Do not repeat B0. Mount LoadingCard/Touch, **not Stack**, in original opaque LevelLoading. Keep loadingRun/token/deadline/RoundLoadingState/readiness/error watchdog logic intact.

Bind Eyebrow/Title/Underbar, Steps/Step1..3/Line (touch Step3 absent), Divider, Tip/TipText, Status/StatusLine + Track/Fill, LevelTrack/Slot1..6. Only title differs for fixed/random mystery2/5; hide eyebrow/steps/divider/tip for2/5, hide steps/tip for6. Tips from DeathAdvice1/3/4. Retire the synchronization title overwrite at2027 and TitleDone only with all reads removed; staged statuses never replace title. Status and non-current slots Sage; current slot accent. Track literal1 · ? · 3 · 4 · ? · 6. No new loading ImageLabel or world transparency.

Loading title6 must come from current Playground client if an honest first objective exists; audit that source after live baseline, not the dormant mall clone. In current source previews have explicit win branches; preserve those gates regardless of inherited plan's historical level-5/6-not-rounds claim.

### SpectateController

Mount SpectateBand/Touch + SpectateBackToLobby. Actual paths Prev/Next, each Arrow and KeyChip; Initial/Letter; Watching; Who. Existing watch targets, first-person camera/body hiding, beam/lighting/audio, SpectateTargetUserId, Escaped+Level2_ExitTransition deferral remain unchanged. Replace label writes in watch(index) with separate Watching/Who; DisplayName and initial, safe nil target copy SPECTATING/NO ONE LEFT TO WATCH. Q/E and D-pad switch; touch44x44 hits.

Transparent band frames BT1, no Soft/no plate. Every band TextLabel contextual Ink stroke1.5px, transparency0.35, thickened2 only if Studio bright-background QA needs it. Attention6s then45% fades stroke too. Current cycling/BackToLobby gate excludes PartyDownCardOpen and RoundExitPromptOpen; retain. Restore known target/name after device remount; do not start/stop camera just because template changed.

## Tests and real QA coverage

| Batch | Offline changes | Studio checks that cannot be inferred from fakes |
|---|---|---|
| Shared/B5 | Grow test_round_hud and copy lint: real fixtures, Stack hidden parts/design size, Fill anchor, Feed merge+expiry+caps, DisplayName, caption gates, clear ownership, retained loss snapshot. Update caller extraction seams without dropping source-level logic checks. | two-player objective/CD/pump emits one row; hidden table player still sees row; captions on/off; phone one-row slot. |
| B6 | New test_prompt_plate exercises real draw/build with prompt fakes and real template; update test_round_exit_hold/controller_input and test_spectator_count REC checks. | two clients REC same time; real prompt hold; pad glyph; Luna action; View1.5s/Stay; small phones have isolated44 door and no REC/brackets. |
| B7 | New test_level3_hiding_hud/test_level4_note_keypad with EndsAt, focus, remount, note reopen, E/B/tap close, Order seam. Existing level4 tests remain. | real Manager table check; gamepad keypad; wrong code; note order/light/film/screen effects unchanged. |
| B8 death | Extend test_death_advice's real do-block fixture loader; nested/recursive label reads; OPEN/DOCKED/CLOSED, serial timers, X/B/Esc/menu Pass paths, no reopen on resize/party, next death reset,44 hits. Whole RoundUI compile. | own versus teammate death, solo killcam/party overlay, touch X, physical Esc/menu fallback, new death after reentry. |
| B8 results/loading | Update round_loading_notice/host extraction, test_reentry_dismissal/dev_free_respawn_offer/controller_input, add actual result/completion block test with real fixtures for stats/choices/pressed labels/flash. Preserve serial/revision and late failure tests. | win/loss/own escape, six-member roster on phone, Continue/Return actions and choices, Achievements toast not on buttons; all six loading data modes. |
| B8 spectate | Existing test_spectate_parity currently targets **SoundController audio**, not GUI. Extend it or add new GUI suite; do not replace audio checks. Test null target, escaped, initial, strokes, no counter, remount, modal exclusion. | two-player POV/cycle, bright Level2 pool and Level4 neon legibility, watched flashlight unchanged. |

UIRegression existing scenario requirements reference HiddenStatus/LeaveHiding (1393), EndingTitle/EndingStats/EndingHint/buttons(1482), and PartyDownCard/Title/Fallen(1512). Update node types/nested paths and text probes with the batch; keep pinned mounted names. UIRegression must not treat transparent wrappers/decorative bands as collisions or silently skip newly imported button targets. Run scoped lanes then whole RunAll after integration, with cleanup restoring test attrs/device input.

The inherited B1/B2 unverified real KIT tap, small-phone/tablet/spectate/shield-capture gaps remain real QA duties. None is closed by this read-only map.
