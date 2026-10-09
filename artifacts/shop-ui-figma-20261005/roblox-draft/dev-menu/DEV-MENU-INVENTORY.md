# Developer menu: inventory and proposed structure (2026-10-06)

This document was produced read-only: nothing in Studio, the repo mirror or git was changed.

Sources:
- `_local/shop-ui-figma/studio-turn/src/ZyntraStore.studio.lua`: the Studio copy of 2026-10-05, newer than the repo. Its DEV tab is at lines 709-1371, the opener at 3733-3970 and the J key at 4130.
- `_local/shop-ui-figma/studio-turn/src/DevAccess.studio.lua` and `ZyntraMonetization.studio.lua` (token grant at 1407-1475).
- Repo mirror:
  - `StarterPlayer/StarterPlayerScripts/`: `DevCheats`, `MasterTuningClient`, `NoiseReporter`, `RoundUI`, `Level 6 CD Dev ESP`, `Level 2 Pool Slide Dev ESP`, `R4DevGateController`, `Level4PreviewPrompt`, `Level2BlenderPreviewButton`, `Level6PreviewTransport`.
  - `ServerScriptService/`: `GameManager` (DevControl at 180-345, DevTuning at 347-372), `Level 2 Systems/Level 2 Objective Controller` (`DevActivatePumpPair`), `Level5PreviewAccess`, `Level6PreviewAccess`, `Level2BlenderPreviewAccess` and `LobbyReimaginedPreview/DevBayAccessGuard`.
  - `ReplicatedStorage/UIRegression` (the DEV lanes).

## 0. Who counts as a developer

`ReplicatedStorage.DevAccess` checks UserIds only.

| Predicate | Who passes | What it gates |
|---|---|---|
| `IsAllowed` | 40920547 mikkelczar, 9488575949 LaverSneglen | The DEV tab, DevCheats, Master Tuning, every `DevControl`/`DevTuning` command, token grants, the Developer suit, the "Developer" nametag and the Level 2 Poolrooms preview. |
| `IsLevel3TimelineOwner` | 9488575949 LaverSneglen only | The SKIP TO BLACKOUT WARNING row. The row is not even built for anyone else. |
| `IsLevel6PreviewAllowed` | `IsAllowed` players, ZenMeister02 (11374988579), and Studio test players with negative ids | The Level 5/6 preview doors, R4 gate shutters, the Level 6 CD ESP and the DevBayAccessGuard. |

Every UI gate is cosmetic. The server re-checks `DevAccess` on every remote. `GameManager` also applies one rate bucket to `DevControl` and `DevTuning` together: 12 commands per 1 s per player.

**Run tainting.** `runDevTouched = true` is set by every `DevControl` command except `fastQueue` and `playerEsp`, and by every applied `DevTuning` write. A tainted round never counts as a record or a challenge. Today the UI does not tell the developer this.

## 1. How the developer menu opens (the "dev phone")

The DEV menu is the last tab of the legacy Zyntra terminal (`ZyntraStore`, ScreenGui `Terminal` > `TerminalContent` > `Dev`). The tab is appended only when `devAllowed` is true. When it is opened from inside a round, the terminal is called the "dev phone".

| Entry | Device | Where | Behaviour |
|---|---|---|---|
| **J** key | keyboard | anywhere | Fires `PlayerScripts.DevPhoneCommand`, which runs `toggleMain`. In a round this jumps to the DEV tab (`selectTab("Dev")`). In the lobby it opens on the last-used tab. |
| **ZYNTRA // DEV** chip | touch, in a round | under the objective readout column, 136 px wide, at least 44 px tall | `toggleMain()`. Placement is chosen from three candidates, so it stays clear of the thumbstick, the controls, Jump and the readout. |
| **UPGRADES** rail button | lobby, any device | lobby rail | `toggleMain()`, then the developer taps the DEV tab. **After the L4 shop patch, with `ShopUIVersion` = `L4`/`L4-dev`, this button opens the L4 window, which has no DEV.** Touch developers then have no lobby route to DEV; keyboard developers still have J. The new menu needs its own lobby entry. |
| `PlayerScripts.DevPhoneCommand` (BindableEvent) | script | - | `toggleMain(optionalBool)`. |
| `PlayerScripts.ZyntraOpenTerminal` | script | lobby | `openKioskShop(tab)`. With `"Dev"` it opens on DEV in the lobby. |

**Close:** Escape, the terminal close button, the character dying, `Escaped = true`, or `RoundActive` becoming false while the player is InRound. An `InRound` change closes it as well.

**Blocked while open:** `QueueModalOpen`. Also `DispatchBriefingOpen`, but only in a round. `toggleMain` also refuses to open over any other screen-owning modal (`UIDevice.ScreenOwningModalOpen()`).

**Published state:**
- `DevPhoneOpen` (only for developers): RoundUI releases the mouse cursor while it is set, and NoiseReporter suppresses input.
- `ZyntraStoreOpen`.
- `UIDevice.SuppressTouchMovement`.

**Heading:** "WHITELISTED DEVELOPER CONTROLS". When keyboard glyphs are allowed (`UIDevice.SuppressesKeyboardGlyphs()` is false), "  //  PHONE: J" is appended. The heading is rebuilt on `UIDevice.Changed`.

**Status line:** the terminal's shared `TerminalStatus` label (`showStatus(message, tone)`) shows every result readback listed below.

## 2. DEV tab: every row (Studio copy, top to bottom)

Rows live in `Dev > DevControls` (a ScrollingFrame). Each row is a `Frame` named after its **command**, with a `RowTitle`, a `Description` and a `Toggle` button. `contract.card("Dev", command, row, toggle)` registers each row for UIRegression.

Every row except the token form follows one path:

UI → `PlayerScripts.DevCheatCommand:Fire(command)` (BindableEvent owned by DevCheats) → DevCheats → `Remotes.DevControl:FireServer(command, bool)` → `GameManager`.

Rows marked *client-local* never reach the server.

**Caption rules:**
- Toggles show `ON`/`OFF` + `//  <key>`.
- Actions show ActionCaption / BusyCaption / DisabledCaption + `//  <key>`.
- The default DisabledCaption is `LEVEL n ONLY`. `UIRegression`'s `Fit.ZyntraDisabledCaptions` matches that pattern.
- `UIDevice.Caption` drops the key half whenever glyphs are suppressed (touch).

| # | Row (label) | Description (as shipped) | Control | Key | Command → what it does | State readback | Availability / gating |
|---|---|---|---|---|---|---|---|
| 0 | **GIVE RESEARCH TOKENS** (form `GrantResearchTokens`) | "Choose a player on this server and enter 1-10,000 tokens." | Form: SELECT PLAYER dropdown (lists players on the server, "(you)" suffix), TOKENS TextBox (default 20, accepts 1-10,000), GIVE TOKENS button | - | **Not DevControl.** `Remotes.ZyntraGrantTokens:InvokeServer(targetUserId, amount)` (RemoteFunction) returns `{Success, Message}`. The server mutates the target's profile, `Tokens += amount`. | Form attributes `Pending` and `SelectedUserId`. Button reads GIVING... while pending and WAIT Ns during the 3 s cooldown. A "still waiting" note appears after 12 s. The result is shown on the form and in the status line. | `IsAllowed` (server). **Desktop only: the form is hidden when `UIDevice.IsTouch()`.** Works in the lobby and in a round. The target must be on this server with a loaded, persistent profile; in Studio the grant is not saved. |
| 1 | **FREE RESPAWN** | "Return after death in this level. No Robux, tokens or credits." | action | - | `freeRespawn` → `GameManager.requestDevRespawn` → `ServerStorage.ZyntraReentry:Invoke(player, true)` (free mode, never touches Monetization) | Busy: `DevRespawnBusy`. Result: `DevRespawnStatus` (RESPAWNED, MUST_BE_DEAD, BUSY, PLACEMENT_FAILED, DEVELOPER_ONLY) plus `DevRespawnSerial`. Captions: RESPAWN / RESPAWNING... / WHEN DEAD. | **In a round, dead only.** Requires `RoundActive` and `InRound`, not `Escaped`, not `Level2_ExitTransition`, the character's Humanoid at Health ≤ 0, and no request in flight. One request per player at a time. |
| 2 | **ESP** | "Highlights objectives and hostile entities through walls." | toggle (default **ON**) | B (B toggles ESP and 3-SECOND QUEUE together) | `esp`, *client-local*. Highlights `DevESP`, labels `DevESPLabel` (Level 4 kinds), Level 1 puzzle items, `Entity`, `Level2HostileEntity`, `Level3HostileEntity` (Mall Manager), Level 3 CDs, `L4DevESP`, `Level4UsherLocal`. | `DevCheatEsp`, mirrored as `DevEspEnabled` (read by the Level 6 CD ESP and the Pool Slide ESP) | Anywhere. Does not taint the run (client-local). |
| 3 | **PLAYER ESP** | "Shows every player through walls, including distant players." | toggle (default OFF), keyless | - | `playerEsp`. The client polls `DevControl("playerEsp", true)` every 0.5 s. The server replies to this developer only, with `FireClient("playerEsp", {At, Players={UserId, Position, Alive}})`. Labels are drawn in `PlayerGui.DevPlayerESP` ("@name", or "@name\nDEAD"). | `DevCheatPlayerEsp` | Anywhere. Does not taint the run. |
| 4 | **3-SECOND QUEUE** | "Shortens the lobby station countdown for rapid testing." | toggle | B (shared with ESP) | `fastQueue` → server sets the player's `DevFastQueue`. A station counts down `FAST_QUEUE_TIME` if any ready member has it. | `DevCheatFastQueue` (mirrors `DevFastQueue`) | **Lobby only**: refused on reserved round servers. Does not taint the run. |
| 5 | **NOCLIP FLY** | Keyboard: "Fly through geometry with WASD, Space and Left Ctrl." Touch: "Fly through geometry using the movement stick." (live swap) | toggle | V | `noclip`. The client anchors the root and flies at 90 studs/s. The server moves the character's parts into the `DevNoclip` collision group. | `DevCheatNoclip` | Anywhere. Refused while `Level2_ForcedSliding`. Turns off on respawn. Taints the run. |
| 6 | **PAUSE ENTITIES** | "Freezes or resumes hostile entity behavior." | toggle | P | `pauseEntity` → `workspace.EntityPaused` | `DevCheatEntityPaused` (mirrors `workspace.EntityPaused`) | Anywhere. **Server-wide**: it affects every player on the server. Taints the run. |
| 7 | **PUSH IMMUNITY** | "Ignores the Level 1 Entity's yell push-back." | toggle | I | `immunePush` → player `DevPushImmune` | `DevCheatPushImmune` (mirrors `DevPushImmune`) | Anywhere. Only matters in Level 1. Taints the run. |
| 8 | **UNLIMITED EQUIPMENT** | "Unlimited flashlight battery and player stamina." | toggle | U | `unlimited`, *client-local*: the player attribute `DevUnlimited`, read by NoiseReporter and FlashlightController | `DevCheatUnlimited` | Anywhere. Matters in a round. |
| 9 | **THIRD-PERSON CAMERA** | "Switches gameplay between first and third person." | toggle | C | `thirdPerson`, *client-local*: CameraMode/zoom. The lobby is always third person. | `DevCheatThirdPerson` | Takes effect **in a round**. The touch POV button mirrors it (section 3). |
| 10 | **PULL TWO PUMPS** | "Pulls the next lever now, then the second 5 seconds later." | action | - | `level2PumpPair` → `Level 2 Objective Controller.DevActivatePumpPair(player)` | Busy: `DevLevel2PumpBusy`. Result: `DevLevel2PumpStatus` plus `DevLevel2PumpSerial`. Statuses: FIRST_PULLED_SECOND_IN_5_SECONDS, TWO_PUMPS_PULLED, SECOND_ALREADY_RUNNING, NEED_TWO_AVAILABLE_PUMPS, SEQUENCE_BUSY, LEVEL_2_ONLY, MUST_BE_ALIVE, FIRST_/SECOND_PUMP_UNAVAILABLE, UNAVAILABLE, CANCELLED_*. Captions: PULL / WAITING 5s / LEVEL 2 ONLY. | **In a round, Level 2 only**: `SelectedLevel == 2`, `RoundActive`, `InRound`, not busy. The server also requires an alive character and two unstarted pumps. |
| 11 | **DROP A BODY** | "A suited body falls past you, screaming. Every second one hits a pillar." | action | O | `level5Fall` (DEV_LEVEL5_FALL_20261005). The server shows the fall to everyone in the level. | Live attribute `Level5VoidRound`. Captions: DROP / LEVEL 5 ONLY. No busy or status attribute. | **In Level 5 only**: `Level5VoidRound == true` and `InRound`. Level 5 is a live level on the lobby server, so `SelectedLevel` and `RoundActive` are not used. |
| 12 | **SKIP TO BLACKOUT WARNING** | "Jumps the active Level 3 song to 2:25 for the five-second warning." | action | K | `level3PreBlackout` → `ServerStorage.Level3DevSkipToPreBlackout:Invoke()` | `DevLevel3TimelineStatus` (SKIPPED_TO_2_25, ALREADY_AT_OR_PAST_WARNING, OBJECTIVE_COMPLETE, NOT_RUNNING) plus `DevLevel3TimelineSerial`. Captions: SKIP / LEVEL 3 ONLY. | **LaverSneglen only.** In a round, Level 3 only: `SelectedLevel == 3`, `RoundActive`, `InRound`. |

### Discrepancies to resolve before wiring (verify against live Studio)

1. **`level5Fall` (DROP A BODY, key O) has no handler in the mirror.** The repo's `DevCheats` dispatch does not handle it and would warn "Unknown command". `GameManager`'s DevControl handler has no branch for it either. No file under `G:\Roblox` contains one. Only the Studio ZyntraStore and `UIRegression` (`DEV_CAPTION_KEYS`) know the command. The handler must live in Studio-only versions of DevCheats and a server script. Pull those first (`pull_source_from_studio.py --audit`).
2. **K and O are captioned as keys but are not bound in the mirror's DevCheats.** Its `InputBegan` binds only B, V, P, I, U and C. Check the live DevCheats. If the keys are unbound, the new menu should drop the glyphs.
3. **GIVE RESEARCH TOKENS is invisible on phones and tablets** (`form.Visible = not UIDevice.IsTouch()`). This is a deliberate gate. The new menu should keep it, or the owner decides otherwise.
4. **The Pool Slide ESP** (`Level 2 Pool Slide Dev ESP`) draws a status panel for a hostile that CLAUDE.md records as deleted on 2026-09-02. Project memory says a Studio-only Pool Slide came back on 2026-09-09. The script is passive (it follows `DevEspEnabled`), so leave it out of the menu.
5. `Level4PreviewPrompt` still hides `Level4DeveloperPreview*` prompts. The Level 4 preview was deleted on 2026-10-05, so those names are dead. It is harmless.

## 3. Other developer surfaces a player can open or see

| Surface | Script | How it opens | What it does | Gate |
|---|---|---|---|---|
| **Master Tuning panel** (`PlayerGui.MasterTuningPanel`, "MASTER TUNING") | `MasterTuningClient` | **F4** (ContextActionService `MongoTVMasterTuning`). No other entry and no bindable. | 42 numeric rows from `MasterConfiguration.Entries`: Level 1 (14), Level 2 (12), Level 3 (14), Lobby (2). Sub-groups: Størrelse, Entitet, Indhold, Mål, Mall Manager, Blackout, Timing. Each row has a `−` / `+` stepper (registry `Step`), a value box (Enter commits, `Coerce` clamps), and a **Nulstil** reset that is enabled only while the value is overridden. Overridden rows are amber with a ● bullet. Writes go to `Remotes.DevTuning:FireServer(key, number\|nil)` → `Master.SetOverride`. Copy is in **Danish**. | `IsAllowed`; works anywhere. Readback: `DevTuningStatus` ("OK" or the reason), `DevTuningSerial` and the `ReplicatedStorage.MasterTuning` attributes. Applied writes taint the run. Some rows note "Træder i kraft ved næste runde-opbygning" ("takes effect at the next round build"). |
| **PARTY DOWN card: FREE RESPAWN** | `RoundUI` (`pd.free`) | The card appears when the last living player dies | A third button that fires `DevCheatCommand "freeRespawn"`. Failures show "FREE RESPAWN // <status>". | `IsAllowed` (cosmetic). The card grows from 268 to 316 px. |
| **Re-entry modal: FREE RESPAWN // DEV** | `ZyntraStore` (`ReentryFreeRespawn`) | The emergency re-entry modal | The same `freeRespawn` command; reads RESPAWNING... while `DevRespawnBusy` is set. | `IsAllowed` (cosmetic) |
| **Touch POV button** (`TouchPOV`, "POV 1ST/3RD") | `NoiseReporter` | Part of the touch control cluster | Fires `DevCheatCommand "thirdPerson"` | Touch, `IsAllowed`, in a round |
| **Player ESP labels** (`PlayerGui.DevPlayerESP`) | `DevCheats` | The PLAYER ESP row | Overlay only | - |
| **Pool Slide ESP status** (`PlayerGui.PoolSlideDevESPStatus`) | `Level 2 Pool Slide Dev ESP` | Automatic while ESP is on and `SelectedLevel == 2` | Text diagnostics, no controls | `IsAllowed` |
| **Level 6 CD ESP** (`Level6CDDevESP` highlights) | `Level 6 CD Dev ESP` | Automatic in Level 6 (`Level6InRound`). For `IsAllowed` players it follows `DevEspEnabled`. ZenMeister02 toggles it with **B**. | Highlights CDs | `IsLevel6PreviewAllowed` |
| **Level 2 Poolrooms preview pedestal** ("ENTER LEVEL 2 POOLROOMS PREVIEW") | `Level2BlenderPreviewButton` + `Level2BlenderPreviewAccess` | A world ProximityPrompt in the Level 2 bay, built for developers only. On touch the Found Footage HUD plate is the button. | `Level2BlenderPreviewRequest:FireServer` → a GameManager developer round (`Level2BlenderPreviewActive`) | `IsAllowed`. Needs: not InRound, not Level6InRound, not a reserved server, not in a queue, and the kit `Ready`. |
| **Level 5 / 6 preview doors** (`Level5/6DeveloperPreviewPrompt` and `…ReturnPrompt`) | `Level5PreviewAccess`, `Level6PreviewAccess`, `Level6PreviewTransport` | World ProximityPrompts (hold 0.5 s) | Teleport into and out of the preview worlds | `IsLevel6PreviewAllowed`. `Level4PreviewPrompt` hides them from everyone else. |
| **R4 lobby gate shutters** | `R4DevGateController` + `DevBayAccessGuard` | World SurfaceGuis on the Level 5/6 bays | Show "DEV PREVIEW" (cyan) for allowed players and "COMING SOON" plus a progress board for everyone else. Not interactive. | `IsLevel6PreviewAllowed` |
| **"Developer" nametag** | `ZyntraMonetization` | Automatic above the head in the lobby | Cosmetic | `IsAllowed` |
| **Developer suit** (skin `Kind = "Developer"`) | `ZyntraSkins` / `ZyntraSkinsPage` | SKINS tab | Owned exactly while DevAccess allows. Equipping is refused for anyone else. | `IsAllowed`. **This belongs to SKINS, not the dev menu.** |

**Not player-openable** (Studio or MCP hooks; out of scope, do not surface):
- `ServerStorage.ZyntraReentry:Invoke(player[, true])`
- `ServerStorage.Level3DevSkipToPreBlackout:Invoke()`
- `workspace.DevSimulateFirstLogin` (an Edit-time flag)
- `UIRegressionZyntraStoreProbe` (Studio only)
- `workspace.ShopUIVersion` (`L4-dev`)

**Keybind summary (developers):**

| Key | Action |
|---|---|
| J | dev phone / terminal |
| B | ESP + 3-SECOND QUEUE |
| V | noclip fly |
| P | pause entities |
| I | push immunity |
| U | unlimited equipment |
| C | third-person camera |
| K | skip to blackout (caption only in the mirror) |
| O | drop a body (caption only in the mirror) |
| F4 | Master Tuning |
| Esc | close the terminal |

The non-developer B binding (ZenMeister02) controls the Level 6 CD ESP only.

## 4. Proposed information architecture for the new menu ("ZYNTRA // DEV", Zyntra Flat)

The plan keeps every existing function and adds no server power. Each row keeps its **command key** as the instance name and keeps the same DevCheatCommand / ZyntraGrantTokens / DevTuning path. Then DevCheats, GameManager and UIRegression's `contract.card("Dev", command, …)` and `DEV_CAPTION_KEYS` keep working. If the row names or captions change, the UIRegression DEV lanes (a mirrored file) need a matching edit.

Six groups, shown as a left nav rail. Opening it in a round lands on **ROUND**, the way `selectTab("Dev")` does today; the lobby lands on **PLAYER**.

| Group | Rows (command) | Where it works |
|---|---|---|
| **1. ROUND** | FREE RESPAWN (`freeRespawn`), PAUSE ENTITIES (`pauseEntity`), PULL TWO PUMPS (`level2PumpPair`), DROP A BODY (`level5Fall`), SKIP TO BLACKOUT WARNING (`level3PreBlackout`, built only for the timeline owner) | **In a round.** PAUSE ENTITIES works anywhere but is server-wide. Rows for other levels stay drawn but disabled, with `LEVEL n ONLY` / `WHEN DEAD`. In a round, sort the current level's action first. |
| **2. PLAYER** | NOCLIP FLY (`noclip`), PUSH IMMUNITY (`immunePush`), UNLIMITED EQUIPMENT (`unlimited`), THIRD-PERSON CAMERA (`thirdPerson`) | Anywhere. THIRD-PERSON only takes effect in a round. PUSH IMMUNITY only matters in Level 1. |
| **3. VISION** | ESP (`esp`), PLAYER ESP (`playerEsp`) | Anywhere. Neither taints the run. |
| **4. LOBBY** | 3-SECOND QUEUE (`fastQueue`) | **Lobby only.** The server refuses it on round servers, so draw it disabled with "LOBBY ONLY" in a round. That is a new caption, so `Fit.ZyntraDisabledCaptions` needs it. |
| **5. ECONOMY** | GIVE RESEARCH TOKENS (`ZyntraGrantTokens` form: player picker, amount 1-10,000, GIVE) | Anywhere. Desktop only today (hidden on touch; owner decision to keep or lift). |
| **6. TUNING** | MASTER TUNING: one row with an OPEN button that toggles the existing F4 panel | Anywhere. Taints the run. **This needs a tiny client hook** (a BindableEvent in `MasterTuningClient`, a mirrored file); it adds no server power. The cheaper fallback is an info row reading "PRESS F4". Restyling the F4 panel itself is a separate, optional job. |

Merge option if six tabs feel heavy: fold LOBBY into ROUND as a "QUEUE" sub-section, and ECONOMY plus TUNING into one **TOOLS** tab, which leaves 4 tabs.

### Row anatomy and state map (for the Figma frames)

- **Row card:** TILE fill, radius 24, 3 px LINE stroke.
  - Title: Montserrat ExtraBold 34, CREAM.
  - Description: SemiBold 32, SAGE, 2 lines max.
  - Control on the right: at least 136 px wide (owner rule) and at least 96 px tall.
- **Toggle:**
  - ON: owned-button style (OWNED_FILL face, 4 px RAIL TEAL stroke, "ON" in Montserrat Black 40, RAIL TEAL).
  - OFF: unavailable style (TILE_HI face, LINE stroke, SAGE "OFF").
- **Action:**
  - READY: ICON TEAL face with a #2D7774 stroke and #1D4F4D shadow, label in TILE colour.
  - BUSY: TILE_HI with SAGE text, e.g. RESPAWNING... / WAITING 5s.
  - DISABLED: TILE_HI with SAGE `LEVEL n ONLY` / `WHEN DEAD`.
  - **Never amber**, because amber means Robux.
- **Key glyph:** a Count-badge chip (TILE_HI, CREAM, Roboto Mono Bold 30) showing B, V, P, I, U, C, K or O. Hide it whenever `UIDevice.SuppressesKeyboardGlyphs()`. This needs keyboard and touch variants. The NOCLIP description also swaps copy per device.
- **Group meta line (SAGE):** for groups that taint the run, "Runs using these do not count for records". This fact is real but not surfaced today. Use plain text, not a new ribbon kind.
- **Header:** "ZYNTRA // DEV", Montserrat Black 64, with the 96x8 ICON TEAL underbar. Eyebrow: "WHITELISTED DEVELOPER CONTROLS" (+ "  //  J" on keyboard). Close slot 120x120 in CORAL. The status line at the bottom is SemiBold 32 SAGE, with success in RAIL TEAL and errors in CORAL.
- **Images: 0.** Nav glyphs can be native, as in the SKINS/DONATE/COLORS tiles. That leaves the whole 15-image Framewisp budget free.
- **Entry points to keep:**
  - J (desktop).
  - The ZYNTRA // DEV touch chip in a round (136 px).
  - `PlayerScripts.DevPhoneCommand`.
  - **A new lobby route for touch developers** once the L4 shop owns UPGRADES. One option is a DEV tab or button in the L4 window header, built only for `IsAllowed` players. This is a UI route, not a server power.
- **Contracts to keep:** `DevPhoneOpen` (only for developers), `ZyntraStoreOpen` or its equivalent screen-owning-modal flag, `UIDevice.SuppressTouchMovement`, the close on death / Escaped / RoundActive=false, and refusal while `QueueModalOpen` is set (and `DispatchBriefingOpen` in a round).
