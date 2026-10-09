# MAP: the legacy Daily Rewards system, end to end (2026-10-07)

Read-only survey for the Figma `DailyRewards_L4` window that replaces it. Line numbers are the
repo mirror at the time of writing. Every file named here is `synced` in `studio-sync-manifest.json`,
and the Shop L4 draft and mirror are byte-identical.

| File | Lines | Role |
|---|---:|---|
| `StarterPlayer/StarterPlayerScripts/Daily Rewards Client.LocalScript.lua` | 646 | The modal shell: gui, header, X, status line, open/close, modal rules. Mounts the page once. |
| `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua` | 875 | The page: strips, progress, 3 milestone cards, CLAIM, research rows, countdown. |
| `ReplicatedStorage/ZyntraDailyResearch.ModuleScript.lua` | 36 | Shared pure ledger. The server needs it; the page `require`s it only for its Goals. **Keep it.** |
| `ReplicatedStorage/ZyntraConfig` `DailyRewards` (lines 66-93) | - | Milestones, wheel and accrual tuning. **Server data. Keep it.** |
| `ServerScriptService/ZyntraMonetization.Script.lua` | 4781 | Answers everything. **Do not change.** |

---

## 1. Daily Rewards Client (the shell)

### What it builds

| Instance | Notes |
|---|---|
| `PlayerGui.DailyRewardsGui` (ScreenGui) | `ResetOnSpawn=false`, `DisplayOrder=117` (the wheel is 118, ZyntraStore 55, Shop L4 56), `ScreenInsets=CoreUISafeInsets`, `ZIndexBehavior=Sibling`. |
| `> DailyRewardsShade` (Frame) | Full size, `BackgroundTransparency=1` (owner 2026-10-07: no backdrop), `Active=true`. This is the input sink. A tap on it does **not** close. Its `Visible` **is** the open state. |
| `> > DailyRewardsPanel` | `UIStyle.panel`. Design size 720x640, clamped to `UIDevice.Layout().ModalViewport` (`MIN_WIDTH` 260, `MIN_CONTENT_HEIGHT` 96). |
| `> > > RewardsHeader` | A white frame under the orange `HeaderGradient`. Holds `HeaderGift` (rbxassetid://117126194981100, Fit), `HeaderTitle` "DAILY REWARDS" (with a UIStroke) and `CloseButton` "X" (48 px floor everywhere, coral 190,60,50, `UIStyle.hover`). |
| `> > > PageContent` | `ClipsDescendants`. The page mounts here. |
| `> > > StatusLine` | A TextLabel for the server's push message. Tone colours: error 244,95,82; success = accent; otherwise muted. |

Panel attributes, published for regression: `DailyRewardsCompact`, `DailyRewardsTapFloor`,
`DailyRewardsContentHeight`, `DailyRewardsModalWidth`, `DailyRewardsModalHeight`.

### Profile plumbing (lines 286-319)

It keeps its own profile copy, the same as ProtectionClient and ShopData:

- One `Remotes.ZyntraGetProfile:InvokeServer()` at boot (line 646) and on every open.
  - A serial drops an answer that is older than a push.
  - A failure with no profile shows "Could not load the Zyntra profile." in red.
- `Remotes.ZyntraProfileChanged.OnClientEvent(profile, message, tone)` replaces the profile, bumps the serial and
  notifies the page.
- A non-empty `message` is shown on `StatusLine` in that tone.

### Opening (lines 533-587)

- **Entry:** `PlayerScripts.OpenDailyRewards`, a BindableEvent. Whichever side loads first creates it (create-if-absent);
  this client creates it at line 579 and ZyntraStore at line 1777.
  - Only ZyntraStore fires it, from two places: the rail `ZyntraRewardsButton.Activated` (line 1910), and
    `openKioskShop("Rewards")` (line 1818), which `PlayerScripts.ZyntraOpenTerminal:Fire("Rewards")` reaches.
  - Nothing in the repo fires `ZyntraOpenTerminal` with "Rewards" today; the route is kept for compatibility.
- **Refusals (`canOpen`):**
  - `InRound == true`;
  - `QueueModalOpen == true`;
  - `UIDevice.ScreenOwningModalOpen()`, i.e. any other modal is up.
  - ZyntraStore's `lobbyModalOpener` applies the same three refusals and `modalBlocksStore()` before it fires.
- **`open()`, in order:**
  1. Clear the status line.
  2. `publishOpen(true)`: `shade.Visible = true`, then `player:SetAttribute("DailyRewardsOpen", true)`, then
     `UIDevice.SuppressTouchMovement(UIDevice.ScreenOwningModalOpen())`. The attribute is written first, so the
     suppression is derived from the complete modal set.
  3. `pageHandle.refresh()` draws from the cached profile, so the panel is never blank.
  4. `refreshProfile()` re-reads.
  5. Bind ButtonB at High priority to close (`ContextActionService` action `"DailyRewardsClose"`). It passes when the
     modal is hidden or `GuiService.MenuIsOpen`.
  6. If the last input was a gamepad, `GuiService.SelectedObject = closeButton`. A gamepad picked up while the modal
     is open also takes focus (`LastInputTypeChanged`).

### Closing (lines 549-606)

- **Triggers:**
  - `CloseButton.Activated`;
  - Escape (unprocessed input);
  - ButtonB;
  - `InRound` becoming true;
  - `QueueModalOpen` becoming true;
  - `workspace.RoundActive` becoming true;
  - `GuiService.MenuIsOpen` becoming true.
- **`close()`:**
  1. `publishOpen(false)`: sets `DailyRewardsOpen` to **nil**, never false, and re-derives the suppression.
  2. Unbind ButtonB.
  3. Clear `SelectedObject` if it was the X.
- **Nothing closes it on respawn.** The gui has `ResetOnSpawn=false`, so it survives.
- **Layout** reruns on `UIDevice.Changed`, and the page gets a `fit` table through `registerLayoutHook`:
  `{Width, Height, ContentWidth, ContentHeight, Compact, Touch, Tap, TabHeight, TabMinWidth}`.

### Studio-only seam (lines 621-643)

`DailyRewardsGui.UIRegressionDailyRewardsProbe` is a BindableFunction with these actions:

- `"open"` and `"close"` drive the real paths, refusals included;
- `"state"` returns `shade.Visible`;
- `"cards"` returns `"Rewards|Playtime5|ClaimButton"`, one line per card;
- `"scrolls"` returns the page's scroll frames.

Nothing in the repo invokes it (UIRegression does not reference it). It exists for a Play-test driver.

---

## 2. ZyntraDailyRewardsPage (the page)

### Data it reads

| Read | Source | Use |
|---|---|---|
| Milestones | `Config.DailyRewards.Milestones`, sorted by Minutes | One card each, named `Milestone<min>`. The key is `tostring(Minutes)`. |
| Reward copy | `rewardLabel(Config, reward)` | Tokens → "1 Research Token" / "N Research Tokens"; Item → `Config.Items[Key].Name`; `EntityShield` → `Config.ProtectionItem.Name` ("Entity Shield"), because the shield is not in `Config.Items`. Plural adds "s". |
| Reward art | the page-local `REWARD_ART`, keyed on `Kind`/`Key` and never on the minutes | Tokens `rbxassetid://93116899475472`, SpeedPotion `120211340805188`, EntityShield `126728249949579`. A gradient pair is kept per reward (the Figma design does not use it). |
| `profile.Daily.Today` / `.Day` | The server's `dailyPublic` | `sameDay = Day == Today` (both are always today on the server; this guard is defensive). |
| `profile.Daily.PlaytimeSeconds` | Server | `played`, which feeds the readout, the bar fill, the caption and each card's state. |
| `profile.Daily.Claimed[key]` | Server | Whether a card is claimed. |
| `profile.Daily.Accruing` | Server (session state) | Appends "  //  COUNTING" to the readout. **The "//" breaks rule 4.** |
| `profile.Daily.SecondsToReset` | Server | `resetAt = GetServerTimeNow() + seconds`, re-anchored on every push and every `refresh()`. |
| `profile.Daily.Research[i].Complete` | Server | Read **by array index** against the client's `require(ZyntraDailyResearch).Goals`, for Title, Detail and Reward. **Fragile.** The profile entries already carry `Key`, `Title`, `Detail`, `Reward` and `Complete`, so bind by `Key` instead. |
| Wheel fields | - | Not read. The wheel left the page with card #104. |

### What it draws and in which states

- **`CountdownStrip > ResetCountdown`:** `"RESETS IN hh:mm:ss  ·  00:00 UTC"`. The suffix is dropped on the
  phone-landscape tier. Unknown shows `--:--:--`.
  - The 1 Hz Heartbeat ticker runs only while `ctx.isVisible()`.
  - When the countdown reaches 0 it calls `ctx.refreshProfile()` once (`rollAsked`) and never zeroes anything locally.
- **`PlaytimeSection > PlayStrip`:**
  - `PlaytimeReadout` shows `"ACTIVE PLAY TODAY  m:ss"`. An hours field appears only when needed (`formatSpan`).
  - `ProgressTrack > Fill` has scale width `clamp01(played / last.Seconds)`, where `last` is 35 min = 2100 s.
  - `ProgressCaption` reads `"<m:ss> to the <N> minute reward"` for the next unreached milestone, otherwise
    `"Every milestone reached today."`, otherwise "".
- **Each `Milestone<min>` card** holds `Threshold` ("5 MIN"), `RewardIcon`, `ClaimedCheck` (a ✓ badge),
  `RewardName`, `ClaimButton` and `ClaimedLabel`. Its state ladder, in priority order:
  1. **claimed:** button hidden (`UIDevice.SetInteractive(false)`), check and "CLAIMED" shown;
  2. **pending:** "CLAIMING...", locked colour 26,34,37, muted text, disabled;
  3. **ready (`played >= seconds`):** "CLAIM", green 70,200,90, enabled;
  4. **otherwise:** `"<m:ss> TO GO"`, locked, disabled.

  Show first, then enable: `SetInteractive` re-enables `Active`, so the state branch must run second.
- **`PlaytimeNote`:** "Only time in an active round counts."
- **`ResearchHeading`:** "DAILY RESEARCH  //  SOLO · NO PURCHASES". **The "//" breaks rule 4.**
- **`Research<Key>`:** one wrapped label reading
  `"COMPLETE  ·  " | "0/1  ·  "` + Title + "\n" + Detail + "\n" + `"RECEIVED +" | "REWARD +"` + n + " RESEARCH TOKENS".
  A completed row turns green.
- **Offline branch:** when `Config.DailyRewards` is nil, it shows "Daily rewards are not configured on this server."
  and hides the body.
- All of it sits in one vertical `ScrollingFrame` named `DailyRewards`. There are three size tiers: phone, tablet and
  pointer.

### The one action: CLAIM (lines 816-826)

On `ClaimButton.Activated`:

1. Refuse if the card is already pending or the button is not `Active`.
2. `await(key)`: one request in flight per key, with a 6 s `ACTION_TIMEOUT`.
3. `ZyntraAction:FireServer("ClaimPlaytimeReward", {Minutes = <number>})`.
4. Re-render, which shows CLAIMING....

The answer:

- **Any** `ZyntraProfileChanged` push clears every pending key, because the push is the answer.
- On timeout it shows "No answer yet. Try again." (error) and re-reads.
- It never grants or claims locally.

### Handle

`mount(page, ctx)` returns `{refresh, destroy}`, and the shell mounts it **once** per session. `ctx` carries:

- the palette and helpers: `COLORS`, `label`, `button`, `corner`, `outline`;
- data: `action(name, payload)`, `profile()`, `onProfile(fn)`, `refreshProfile`;
- the shell hooks: `showStatus`, `registerLayoutHook`, `isVisible`;
- `contract.scroll`/`card`, which write the `ZyntraPage`/`ZyntraCardKey` attributes;
- `pageName = "Rewards"`.

---

## 3. ZyntraDailyResearch and Config.DailyRewards

`ZyntraDailyResearch.Goals`, in order. **The Detail strings differ from the Figma copy.**

| Key | Title | Detail (live) | Figma text | Reward |
|---|---|---|---|---:|
| Fuse | Restore power | Personally insert a fuse in Level 1. | Insert a fuse in Level 1. | 1 |
| Lever | Open the route | Personally activate a powered lever in Level 1. | Pull a powered lever in Level 1. | 1 |
| Clear | Return with research | Escape any level alive. | Escape any level alive. | 2 |

- **`Normalize`:** builds the saved form, `{Fuse=bool, Lever=bool, Clear=bool}`.
- **`Complete(data, key)`:** sets the flag and adds `Reward` tokens to `data.Tokens` in the same transform.
- **`Public(saved, sameDay)`:** the array the client receives, `{Key, Title, Detail, Reward, Complete}` x3.

`Config.DailyRewards`:

- `AfkGraceSeconds=90`, `ActivityMinimumStuds=1`, `FlushIntervalSeconds=60`.
- `Milestones`:
  - `{5, Tokens 1}`;
  - `{15, Item SpeedPotion 1}`;
  - `{35, Item EntityShield 1}`.
- `Wheel`: six prizes, Token1/Token3/Potion1/Potion2/Shield1/Skin5, with weights 40/20/20/5/10/5. They are read by
  the Lucky Wheel Client and its L4 skin, not by the daily page.
- **No art ids live in Config.** The milestone art is in the page's `REWARD_ART`; the header gift is in the shell.
  `Config.Items[*].IconId` is the shop's crate art, which is different.

---

## 4. The server (ZyntraMonetization; read only, do not change)

### Remotes

All of them are created by `ensureRemote` under `ReplicatedStorage.Remotes`.

| Remote | Direction | Payload |
|---|---|---|
| `ZyntraGetProfile` (RemoteFunction) | client → server | none. It waits up to 10 s for the session, then returns `enrichedPublicProfile` (nil if there is no session). |
| `ZyntraProfileChanged` (RemoteEvent) | server → client | `(profile, message, tone)`. Tone is `"success"`, `"error"` or `"info"`. Every write fires it. |
| `ZyntraAction` (RemoteEvent) | client → server | `("ClaimPlaytimeReward", {Minutes = 5\|15\|35})`. Also `"SpinDailyWheel"`, `"ClaimWheelPrize"` and `"MarkRewardsIntroSeen"`, each with no payload. |
| `ServerStorage.ZyntraResearchProgress` (BindableEvent) | server only | `(player, "Fuse"\|"Lever")`, fired by PuzzleManager at lines 1582-1583 (a fuse inserted) and 1680-1681 (a powered lever pulled). |

### `profile.Daily` (`dailyPublic`, lines 638-661)

```
Day = Today = os.date("!%Y-%m-%d")          -- always today (presented through the pending roll)
PlaytimeSeconds = saved (if same day) + this session's unflushed seconds
Claimed = { ["5"]=true, ... }               -- today only
Research = { {Key,Title,Detail,Reward,Complete}, x3 }
WheelDay, WheelLast = {Day, Key, Serial, Claimed, SkinId?, FallbackTokens?, PaidTokens?}
SecondsToReset = 86400 - os.time() % 86400  -- the next 00:00 UTC
Accruing = this second counts (session state)
```

- **Tokens:** `profile.Tokens` is the only source for the "37 TOKENS" pill. It is not a player attribute.
- **Day roll:** `rollDaily` zeroes `PlaytimeSeconds`, `Claimed` and `Research` lazily, inside the next daily
  transaction. `WheelDay` is not reset; it is compared to today.

### Playtime accrual

- **The 1 Hz loop (lines 3393-3415).** A second counts (`playtimeCounts`) only when all of these hold:
  - `InRound`;
  - `workspace.RoundActive`;
  - `RoundLoadingState == "ready"`;
  - not `Level2_ExitTransition`;
  - and, if alive, the player moved 1 stud within the last 90 s or is `Level3_Hiding`.
  - Spectating counts: the player is dead, escaped or has no humanoid.
- **Flush.** Every 60 s, at every `RoundActive` change, and when a session closes, unflushed seconds are flushed into
  the save through `dailyMutate`. The flush identity is idempotent.
- **Attribute.** The server also sets `player.ZyntraDailyAccruing` (a bool) whenever counting flips. **No client reads
  it today**; the page reads `Daily.Accruing` from the profile, which only updates on a push. For a live "COUNTING"
  chip, the attribute is the better read.

### Claim (`claimPlaytimeReward`, lines 3549-3584)

- **Rate window.** `ClaimPlaytimeReward` is a write-bearing action with a 1 s window, keyed per Minutes. A press
  inside the window is **dropped silently**, with no push. The client's 6 s timeout covers that.
- **Refusals (each answers with a push carrying an error message):**
  - "You already claimed the %d minute reward today.";
  - "Play %d minutes of a round today to claim this. You are at %d minutes.";
  - "Checking your Token Earner pass. Try again in a moment.";
  - "That reward is unavailable right now.".
  - An unknown Minutes value, or no session, returns **silently**.
- **Success.** `applyReward` pays tokens multiplied by the Token Earner tier (x2/x3/x5), an item, or a Protection
  charge for EntityShield. Then `Claimed[key] = true` in the same transform. The push message is
  `"<label> collected -- <N> minutes of play today."`, and the label names the **paid** amount, so a 5x owner reads
  "5 Research Tokens".
- The legacy page always shows the base amount ("1 Research Token", "+1").

### Research

- **Completion is automatic.** The client sends nothing.
  - Fuse and Lever arrive through `ZyntraResearchProgress`.
  - Clear is completed inside the level-completion transform (lines 4161-4162, tracked clears only).
- **The push** says "Daily research complete: +n Research Token(s)". The amount includes the Token Earner bonus.

### Wheel

The Lucky Wheel Client owns the wheel, and the daily window only reads it.

- **Spin.** `SpinDailyWheel` refuses when a prize is still owed ("Collect your prize first: ...") or when the player has
  already spun today ("Today's spin is done: ... Next spin at 00:00 UTC.").
- **Collect.** `ClaimWheelPrize` pays the prize.
- **Free spin ready** = `WheelLast.Claimed ~= false and WheelDay ~= Today`.
- **Prize waiting** = `WheelLast.Claimed == false`, from any day.

### Rewards intro

`MarkRewardsIntroSeen` is idempotent. ZyntraStore owns the intro card, and it stays.

---

## 5. Who else calls or reads it

| Consumer | What it touches | Fate once the legacy window is deleted |
|---|---|---|
| **ZyntraStore** | The rail `ZyntraRewardsButton` (line 271) and its `NotificationDot` (line 307). `rewardsClaimable(profile)` (lines 312-324) lights the dot for any milestone reached and unclaimed; `wheelClaimable` covers the wheel. Both recompute on every push, plus one re-read at `SecondsToReset + 1` (lines 1182-1201). `lobbyModalOpener("OpenDailyRewards")` (lines 1772-1793); `openKioskShop("Rewards")` (line 1818); `railAvailable` uses `SetInteractive` and stands the rail down while any modal is up (lines 1549-1556). The `RewardsIntroCard` text names "REWARDS" and "WHEEL". | **Keep as is.** The new window must create or own `PlayerScripts.OpenDailyRewards` (a BindableEvent) and publish `DailyRewardsOpen`. The dot needs nothing from the window. The comments at lines 164, 647-653 and 1531-1548 name "Daily Rewards Client" and should be updated. |
| **Zyntra Shop L4 `skinDaily`** (lines 1319-1382, `run(...)` at line 1401) | Waits 10 s for `PlayerGui.DailyRewardsGui`. Recolours the shade, panel, header, title, X and StatusLine. Grafts `TokenPill` into the header (its "+" is hidden, the count joins `ui.counts`, and it shows at a header width of 900 px or more). Re-skins each `Milestone%d+` card through `DescendantAdded`. | **Delete** `skinDaily` and its `run(...)` line, otherwise it waits 10 s and warns "daily rewards skin skipped". The shop harness checks at lines 1977-1990 and 2339-2365 must be rewritten to the new rule, and the harness's `legacyDaily` fixture (lines 612-645) goes. The dump round-trip at 2549 keeps `DailyRewards_L4`. |
| **Lucky Wheel Client** | Refuses to open while `ScreenOwningModalOpen()` is true, which includes `DailyRewardsOpen`. Its takeover disables every other ScreenGui while it is open (the daily gui as well, but the two can never both be open). It owns `PlayerScripts.OpenLuckyWheel`. | Unchanged. **A SPIN button in the daily window must close the daily window first** (clear `DailyRewardsOpen`), then `OpenLuckyWheel:Fire()`, otherwise the wheel refuses. Do not fire `SpinDailyWheel` from the daily window: the replay and COLLECT live in the wheel. |
| **UIDevice** | `SCREEN_OWNING_MODALS` contains `"DailyRewardsOpen"` (line 1645). | **Keep the attribute name.** Through `ScreenOwningModalOpen` / `OnScreenOwningModalChanged` it stands down these: RoundUI (8 refs), FlashlightController, NoiseReporter, ProtectionHUD, PuzzleUI, SpectateController, Round Exit Client, Friend Boost Client, Shop Display Client, Level 2 Objective UI, Level2AlertClient, Level 3/6 Reader Clients, ZyntraDetectorClient, Zyntra Shop L4 and Zyntra Dev L4. |
| **RoundUI** | Never names Daily Rewards. It reads it only through the modal set above. | No change. |
| **UIRegression** | `Fit.ZyntraDisabledCaptions` contains "CLAIMED", "CLAIMING", "%d+:%d+ TO GO", "SPUN TODAY", "SPINNING" (line 5313). The rail rows name `ZyntraRewardsButton` (lines 1109, 5471). The comment at line 5547 says REWARDS is not a terminal tab. It never opens the daily modal or invokes its probe. | Keep the captions if the new window uses the same state words. No code change is required. |
| **ShopData** (ZyntraShopUI) | Has no daily code. `ShopData.profile()` / `tokens()` / `Changed` / `Message` already read the same profile and pushes. One instance per client (`start()` is idempotent). | It can be reused as the data source: `profile().Daily`, `tokens()` for the pill, `Message` for the status line. But `purchase()` has no claim route and `sendAction` is local, so CLAIM needs either a new `ShopData.claim(minutes)` that reuses `begin`/`sendAction` (which already respect the 1.1 s write window and the 6 s timeout), or its own `FireServer`. |

### Tests (current status, run 2026-10-07 with luau 0.737)

| Test | Status | What happens to it |
|---|---|---|
| `tools/tests/test_daily_rewards_page.py` | **pass**, 521 checks | Runs the real page. It slices the COLORS/helpers out of ZyntraStore by marker. **Deleted or replaced along with the page.** |
| `tools/tests/test_daily_rewards_client.py` | **FAILS at HEAD**, a stale fake: line 2703 "attempt to index nil with 'Connect'" | Already noted in go-live/MAP-consumers.md. **Deleted or replaced along with the client.** |
| `tools/tests/test_daily_rewards.py` (the server) | **FAILS at HEAD**: "harness has no module ZyntraSkins" | Tests the server only. Unaffected by the UI swap; its stale harness is a separate fix. |
| `tools/tests/test_lucky_wheel_client.py` | **FAILS at HEAD**: "missing fixture child: ZyntraSkins" | Names `DailyRewardsOpen` in its modal list only. Unaffected. |
| `tools/tests/test_zyntra_store_compact.py` | **pass**, 485 | Asserts that `OpenDailyRewards` exists and that REWARDS fires it (lines 584-618), and that `ZyntraDailyRewardsPage` does **not** become a terminal tab (lines 243-260). It stays valid after deleting the page; the module's absence is fine. |
| `tools/tests/test_friend_boost.py`, `test_item_inventory.py`, `test_leaderboard_backfill.py`, `test_level4_clear_persistence.py`, `test_support_product_receipts.py` | (not run) | They use `ZyntraDailyResearch` or the `DailyRewardsOpen` name only. Unaffected as long as both stay. |
| Shop harness `roblox-draft/tests/test_zyntra_shop_l4.py` | **pass**, 1283 | The `skinDaily` checks must be rewritten (see above). |
| Dev harness `dev-menu/tests/test_zyntra_dev_l4.py` | **pass**, 6861 | Names `DailyRewardsOpen` in its modal list only. Unaffected. |

---

## 6. The Figma template against the legacy window (dump `tests/framewisp-dump.DailyRewards_L4.json`, 230 nodes)

The import is export frame **91:331** (`daily-l4/figma-91-331-export-frame.png`), **not** the design page 52:2164
(`figma-52-2164-design-page.png`). The owner's screenshot is 52:2164. Differences that matter:

1. **The LUCKY WHEEL row is not in the import.** L4-ROBLOX-PLAN.md section 1.4 says: "WheelLink ... is not exported
   ... an owner question". The owner's new screenshot now shows it. The row has to come from a re-export (Framewisp,
   at a cost of 1 conversion) or be built in code to match. The right column of the import ends after `ResearchClear`.
2. **The images are placeholders.**
   - `HeaderGift` and all three `RewardIcon`s are `rbxassetid://116221992818153`; in the export PNG they are an empty
     box.
   - At runtime, set the gift to 117126194981100 and the reward art from `REWARD_ART`: 93116899475472 /
     120211340805188 / 126728249949579, keyed on the reward's `Kind`/`Key`.
3. **Text baked into ImageLabels** (static, which is acceptable):
   - `Eyebrow` "ZYNTRA DAILY";
   - `TokenPill/TokenLabel` "TOKENS";
   - `PlayStrip/Label` "ACTIVE PLAY TODAY";
   - `CountdownStrip/Label` "RESETS IN";
   - `SectionHelper` "SOLO · NO PURCHASES".
   - **`Milestone5/RewardName` is also an ImageLabel** (baked "1 Research Token"). The other two cards have
     TextLabels. Replace it with runtime text from `rewardLabel`, the way Shop L4 handles its baked `PendingText`.
4. **Dark backdrop.** The root `DailyRewards_L4` has `BackgroundColor3` 5,9,11 and `BackgroundTransparency` 0, and
   there is **no `Dim` layer**. Make the root transparent and create a transparent, Active `Dim` (the Shop L4
   `ui.build` pattern, lines 101-128).
   - The root carries a `UIAspectRatioConstraint`; remove it.
   - `DailyRewardsModal` imports with ZIndex 4 over a root of 1, so set `art.ZIndex = 1` and `holder.ZIndex = 2`
     (rule 1).
5. **Name collision: `StatusLine`.** In the import, `StatusLine` is the "Only time in an active round counts." note;
   in the legacy shell it is the server-message line. Bind the note as static, and route push messages somewhere else
   (a toast, or a slot that is not in the import).
6. **States the design has no layer for:**
   - claimed (`ClaimedCheck` / `ClaimedLabel` in legacy). In the import `ClaimSlot/ClaimButton/State` is the only
     state text, so CLAIMED is presumably a disabled State;
   - "CLAIMING...";
   - the "Every milestone reached today." caption;
   - the offline branch;
   - "COUNTING".
7. **Progress ticks.** `Tick5` and `Tick15` sit at `Minutes/last` (5/35 and 15/35 of the track); they are confirmed
   by pixel against the design. The track's end is 35. Position them from Config at runtime, not from the import.
8. **Research binding.** `ResearchFuse` / `ResearchLever` / `ResearchClear`, each with `Done/Value` ("1/1"|"0/1"),
   `Info/Name`, `Info/Detail` and `Reward/Amount` ("+n"). Bind by the profile entry's `Key`. A done row has a filled
   teal `Done` chip.
9. **Auto-layout wrappers.** Rows sit under `Items` frames (Framewisp auto-layout). Search descendants by name
   (rule 7). The two hidden `BuyShadow`s on Milestone15/35 are the design's "not ready" look, not a missing reveal.
10. **Header pill "+" (`AddTokens`).** Legacy hid it, because the shop cannot open over a modal. In the new window it
    can work: close daily, then `PlayerScripts.ZyntraShopUIOpen:Invoke("Shop", "Tokens20")`. That is exactly what Shop
    L4's own "+" does (line 1040).
11. **Copy differences.** Design "Insert a fuse in Level 1." / "Pull a powered lever in Level 1." against the live
    "Personally insert ..." / "Personally activate ...". Use the server's `Detail` (the truth), or ask the owner.
    Either way the runtime text must not clip (rule 5).

---

## 7. What the new window must reproduce

### Actions

| # | Control | Does |
|---|---|---|
| A1 | `ClaimButton` on `Milestone<min>` | `ZyntraAction:FireServer("ClaimPlaytimeReward", {Minutes = min})` (a number). Only when ready (`played >= min*60` and not claimed) and not pending. One request in flight per key. Hold a re-press for at least 1 s so it is not dropped by the server window. Any push clears pending. After 6 s with no answer: "No answer yet. Try again." and a re-read, never a local grant. |
| A2 | `CloseButton` | Close. |
| A3 | Escape, gamepad ButtonB (High priority, passes when hidden or the Roblox menu is open) | Close. |
| A4 | `AddTokens` "+" | Close, then `ZyntraShopUIOpen:Invoke("Shop", "Tokens20")`. Or hide it, as legacy does. |
| A5 | LUCKY WHEEL row SPIN (needs the re-export or a code-built row) | Close, then `PlayerScripts.OpenLuckyWheel:Fire()`. Never `SpinDailyWheel`. |
| A6 | Open, through `PlayerScripts.OpenDailyRewards` (a BindableEvent, create-if-absent) | Refuse if `InRound`, `QueueModalOpen` or `UIDevice.ScreenOwningModalOpen()`. Otherwise: show, set `DailyRewardsOpen = true`, `SuppressTouchMovement(ScreenOwningModalOpen())`, draw from the cached profile, `ZyntraGetProfile` re-read, bind ButtonB, focus the X on a gamepad. |
| A7 | Auto-close | On `InRound`=true, `QueueModalOpen`=true, `workspace.RoundActive`=true, or `GuiService.MenuIsOpen`=true. |
| A8 | Close semantics | Hide, set `DailyRewardsOpen = nil`, re-derive `SuppressTouchMovement(ScreenOwningModalOpen())`, unbind ButtonB, clear `SelectedObject`. |
| A9 | Gamepad picked up while open | Focus the X. |
| A10 | Studio probe (recommended, for the main session's real hit tests) | open, close, state, and cards (`"Rewards\|Playtime5\|ClaimButton"` lines). |

### Readbacks

| # | Layer (import name) | Source | Format |
|---|---|---|---|
| R1 | `TokenPill/TokenCount` | `profile.Tokens` (`ShopData.tokens()`) | integer; "--" before the profile has loaded |
| R2 | `PlaytimeReadout` | `Daily.PlaytimeSeconds` | `m:ss`, with `h:mm:ss` from 1 h |
| R3 | `ResetCountdown` | `Daily.SecondsToReset`, re-anchored on every push, open and refresh; local ticks against `workspace:GetServerTimeNow()` at 1 Hz while visible | `hh:mm:ss`; `--:--:--` when unknown. At 0, re-read once. |
| R4 | `ProgressTrack/Fill` | `played / lastMilestone.Seconds`, clamped to 0..1 | scale width |
| R5 | `Tick<min>` | `min / lastMin` for every milestone except the last | scale X |
| R6 | `ProgressCaption` | the next unreached milestone | `"<m:ss> to the <N> minute reward"`, then `"Every milestone reached today."` |
| R7 | `Milestone<min>/Threshold` | Config | `"<min> MIN"` |
| R8 | `Milestone<min>/RewardName` | `rewardLabel(Config, reward)` | "1 Research Token", "1 Speed Potion", "1 Entity Shield" |
| R9 | `Milestone<min>/Art/RewardIcon` | `REWARD_ART` by `Kind`/`Key` | image id |
| R10 | `Milestone<min>/ClaimButton/State` + enabled | `Claimed[key]`, pending, `played` | CLAIMED (disabled) / CLAIMING... (disabled) / CLAIM (enabled) / `"<m:ss> TO GO"` (disabled) |
| R11 | `Research<Key>/Done/Value` + chip fill | `Daily.Research[*]` where `.Key == Key`, field `.Complete` | "1/1" (filled) / "0/1" |
| R12 | `Research<Key>/Info/Name`, `/Detail`, `/Reward/Amount` | `Title`, `Detail`, `"+" .. Reward` from the same entry | runtime text, never clipped |
| R13 | (no layer) COUNTING | `player.ZyntraDailyAccruing` (live) or `Daily.Accruing` | optional; never with "//" |
| R14 | LUCKY WHEEL row status | `Daily.WheelLast` / `WheelDay` / `Today` | `Claimed == false` → prize waiting (COLLECT); `WheelDay ~= Today` → "FREE SPIN READY"; otherwise spun today (the wheel's own copy: next spin at 00:00 UTC) |
| R15 | Server message | the `ZyntraProfileChanged` message and tone (`ShopData.Message`) | success/error/info; **not** the import's `StatusLine` (see section 6.5) |
| R16 | `DailyRewardsOpen` (player attribute) | the window | `true` while open, `nil` when closed |
| R17 | Offline | `Config.DailyRewards == nil` | "Daily rewards are not configured on this server."; no CLAIM |

### Deletion list (the owner's rule: replace AND delete)

- `StarterPlayerScripts."Daily Rewards Client"`: replaced by the new window, which takes over `OpenDailyRewards`,
  `DailyRewardsOpen` and the modal rules.
- `ReplicatedStorage.ZyntraDailyRewardsPage`: nothing else requires it.
- `skinDaily` in Zyntra Shop L4, in both the draft and the mirror.
- `tools/tests/test_daily_rewards_page.py` and `test_daily_rewards_client.py`: replace them with a test of the new
  window.
- **Keep:**
  - `ZyntraDailyResearch` (the server and other tests use it);
  - `Config.DailyRewards`;
  - every server path;
  - ZyntraStore's rail button, dot, opener and intro card;
  - the `DailyRewardsOpen` name in UIDevice.
