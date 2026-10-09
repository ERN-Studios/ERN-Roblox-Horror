# Claude contracts — 2026-09-16 batch (single source of truth for names)

Every agent builds against THIS file. If you need a name that is not here, propose it in
your report; do not invent a second name for something already listed. Baseline: git
`aa40f70`, Studio v1907. Nothing is committed by agents; nothing touches Studio.

## Owner decisions that bind everyone (from OWNER-BRIEF.md + owner-answers.md)
- Playtime milestones (active round play today, one claim each per UTC day):
  5 min -> 1 token, 15 min -> 1 Speed Potion, 35 min -> 1 Entity Shield charge.
- Wheel, ONE free spin per UTC day, five prizes with server weights 45/20/20/5/10:
  1 token, 3 tokens, 1 Speed Potion, 2 Speed Potions, 1 Entity Shield. Show the real odds.
- Speed Potion: 3 tokens each, stored consumable, +10% movement speed for 6 s, max ONE use
  per round, no stacking, no stamina change. Route Marker Pack: 2 tokens -> 3 markers,
  max 3 active per player, team-visible, removed at round end.
- REJECTED, do not build: Flashlight Casings, Results Frame, any substitute cosmetic or
  currency, paid spins, new Robux products, price changes, Discord, Level 2 sounds.
- Shop HUD button returns to SQUARE like its neighbours (the circular treatment from #88 goes).
- Level 3 hide animation, Level 3 Configuration / Hiding Controller / Table Hiding Client,
  assets/animations, animation tools: CODEX ONLY. Do not open those files.

## Profile schema additions (ZyntraMonetization, owner: A-SERVER)
Profile `Version` stays 4; every field is additive and normalised defensively.
```
Items      = { SpeedPotion = 0, RouteMarker = 0 }            -- stored consumables (integers >= 0)
Daily      = { Day = "YYYY-MM-DD",           -- UTC day the counters belong to
               PlaytimeSeconds = 0,          -- active round play accrued that day
               Claimed = {},                 -- milestone minutes claimed, STRING keys: ["5"]=true
               WheelDay = nil,               -- "YYYY-MM-DD" of the last spin, nil = never
               WheelLast = nil }             -- { Day=, Key=, Serial= } prize record of the last spin
FieldNotes = { Discovered = {}, Serial = 0 } -- Discovered[noteId] = true, STRING note ids
```
Entity Shield charges stay in `Protection.Charges` (never bump `Protection.Revision` or touch
`LastOperation` when a reward adds a charge).

## Public profile additions (ZyntraProfileChanged / ZyntraGetProfile payload)
```
Items = { SpeedPotion = n, RouteMarker = n }
Daily = { Day, PlaytimeSeconds (INCLUDING unflushed seconds), Claimed, WheelDay, WheelLast,
          Today = "YYYY-MM-DD" (server UTC day now), SecondsToReset = n (to next 00:00 UTC),
          Accruing = bool (true while this player is currently earning) }
FieldNotes = { Discovered = {...}, Count = n, Total = N, TitleUnlocked = bool }
SpeedBoostUntil = serverTime or 0
```

## Player attributes (server-set on the Player unless stated; replicate to all clients)
| Attribute | Type | Writer | Meaning |
|---|---|---|---|
| `ZyntraSpeedPotions` | number | A-SERVER | stored potions |
| `ZyntraRouteMarkers` | number | A-SERVER | stored markers |
| `ZyntraSpeedBoostUntil` | number | A-SERVER | `workspace:GetServerTimeNow()` when the boost ends; 0 = none |
| `ZyntraSpeedBoostMultiplier` | number | A-SERVER | 1.10 while boosted, else 1 |
| `ZyntraSpeedPotionUsedThisRound` | bool | A-SERVER | true after a use until the round closes |
| `ZyntraFieldNotesTitle` | string | A-SERVER | "" or the completion title |
| `ZyntraDailyAccruing` | bool | A-SERVER | true while playtime is accruing (HUD hint only) |
| `RouteMarkersActive` | number | A-ITEMS | markers this player currently has placed (0..3) |

## ZyntraAction remote (client -> server, existing RemoteEvent `Remotes.ZyntraAction`)
| action | payload | server rule |
|---|---|---|
| `ClaimPlaytimeReward` | `{Minutes = 5|15|35}` | one claim per milestone per UTC day; refuses below the threshold; grants inside ONE profile transaction |
| `SpinDailyWheel` | nil | one spin per UTC day; prize picked and recorded inside the transaction BEFORE any reply; a second call the same day re-pushes the recorded result, grants nothing |
| `BuyItem` | `{Key = "SpeedPotion"|"RouteMarker"}` | token spend + inventory add in one transaction; refuses without tokens |
| `UseSpeedPotion` | nil | in round, alive, RoundActive, RoundLoadingState "ready", not Escaped/Level2_ExitTransition/Level3_Hiding, not already used this round; consumes 1 potion in the transaction, THEN sets the boost attributes |
Responses arrive as the usual `ZyntraProfileChanged(profile, message, tone)` push. Existing
1 s per-action write window applies (WRITE_BEARING_ACTIONS).

## ServerStorage.ZyntraInventory (BindableFunction, owner: A-SERVER; callers: A-ITEMS, A-NOTES)
```
ZyntraInventory:Invoke("Count", player, "RouteMarker")           -> number
ZyntraInventory:Invoke("Consume", player, "RouteMarker", 1)      -> ok: boolean, message: string
ZyntraInventory:Invoke("DiscoverNote", player, level)            -> changed: boolean, noteId: string?, message: string
```
Consume is a durable transaction (mutate). It returns false when the player has too few, the
profile is not loaded, or the write failed; callers must NOT apply the effect on false.
DiscoverNote takes the LEVEL number (1..3), reads `ReplicatedStorage.ZyntraFieldNotes`
(`Notes` array of `{Id, Level, Title, Body, Stamp}`, ids like "L1-01", sorted by Id), grants the
FIRST note of that level the player has not discovered yet, and returns its id. When every
note of that level is already owned it returns `false, nil, "Every note on this level is
already in your collection"`. It awards the completion title (attribute + name tag) inside
the same transaction when Count reaches Total. If the module is absent it returns
`false, nil, "Field notes unavailable"`.

## Remotes / instances created by this batch
| Name | Class | Where | Owner |
|---|---|---|---|
| `Remotes.RouteMarker` | RemoteEvent | ReplicatedStorage.Remotes | A-ITEMS (server creates it) |
| `Remotes.FieldNote` | RemoteEvent | ReplicatedStorage.Remotes | A-NOTES (server creates it) |
| `ServerStorage.ZyntraInventory` | BindableFunction | ServerStorage | A-SERVER |
| `workspace.RouteMarkers` | Folder | workspace | A-ITEMS |
| `workspace.FieldNotes` | Folder | workspace | A-NOTES |

`Remotes.RouteMarker`: client fires `("place")`. Server reads the character's own
HumanoidRootPart (never a client CFrame), validates, consumes 1 marker through ZyntraInventory,
spawns the marker. Server answers `("placed", activeCount)` / `("refused", reason)`.
`Remotes.FieldNote`: server -> client `("discovered", noteId)` and `("alreadyLogged", noteId)`
when the player triggers a note prop; client -> server nothing (ProximityPrompt is server-side).

## New scripts (created in Studio LATER by the lead; agents write the mirror files only)
| Mirror path | Class | Owner |
|---|---|---|
| `ReplicatedStorage/ZyntraDailyRewardsPage.ModuleScript.lua` | ModuleScript (client UI page) | A-REWARDS-UI |
| `ReplicatedStorage/ZyntraFieldNotes.ModuleScript.lua` | ModuleScript (note content, shared) | A-NOTES |
| `ReplicatedStorage/ZyntraFieldNotesPage.ModuleScript.lua` | ModuleScript (client UI page) | A-NOTES |
| `ServerScriptService/FieldNotesService.Script.lua` | Script | A-NOTES |
| `StarterPlayer/StarterPlayerScripts/Field Notes Client.LocalScript.lua` | LocalScript | A-NOTES |
| `ServerScriptService/RouteMarkerService.Script.lua` | Script | A-ITEMS |

## Terminal page module API (ZyntraStore mounts these; owner of the mount: A-SHOP-UI)
Both page modules export exactly:
```lua
return { mount = function(page: Frame, ctx): Handle }
-- ctx = {
--   player, Config (ZyntraConfig), UIStyle, UIDevice,
--   COLORS,                       -- ZyntraStore's palette table (bg, card, accent, accent2, text, muted, line, error)
--   label(parent, text, size, position, textSize, color, font) -> TextLabel,   -- ZyntraStore's helpers
--   button(parent, text, size, position) -> TextButton,
--   corner(parent, radius) -> UICorner, outline(parent, color, transparency, thickness) -> UIStroke,
--   action(name: string, payload: any?),        -- fires Remotes.ZyntraAction
--   profile(): table?,                          -- latest public profile the terminal holds
--   onProfile(fn(profile, message, tone)),      -- subscribe to pushes; returns a disconnect fn
--   refreshProfile(),                           -- re-invoke ZyntraGetProfile
--   showStatus(message, tone),                  -- the terminal's status line
--   registerLayoutHook(fn(fit)),                -- fit = {Compact, Touch, ContentWidth, ContentHeight, TabHeight, ...}
--   isVisible(): boolean,                       -- the terminal and this page are showing
--   contract = { scroll(pageName, scrollingFrame), card(pageName, key, cardFrame, actionButton) },
--   pageName = "Rewards" | "Notes",
-- }
-- Handle = { refresh = function(), destroy = function() }
```
The page module never yields at require time, never requires ZyntraStore, never touches other
pages, and draws only inside `page`. If a page module is missing in Studio, ZyntraStore skips
that tab (guarded FindFirstChild), so the terminal keeps working.

## Keys (verified unused in every client script, 2026-09-16)
| Action | Keyboard | Touch | Owner |
|---|---|---|---|
| Entity Shield | Q (existing) | ProtectionUse slot (existing) | A-HUD |
| Speed Potion | T | new control slot `SpeedPotionUse` | A-HUD |
| Place Route Marker | X | new control slot `RouteMarkerPlace` | A-HUD |
| Back to lobby (hold 1.5 s) | L | hold the chip | A-EXIT |
Already taken: WASD, Space, Shift, Ctrl, F, Q, E, G, H, M, N, R, J, B, V, P, I, U, C, F4, Esc, I/O (Roblox zoom), Tab, `/`.

## ZyntraConfig additions (owner: A-SERVER; everyone else READS them)
```lua
Items = {
  SpeedPotion = { Name = "Speed Potion", TokenCost = 3, DurationSeconds = 6, SpeedMultiplier = 1.10,
                  MaxUsesPerRound = 1, Description = "..." },
  RouteMarker = { Name = "Route Marker Pack", TokenCost = 2, PackSize = 3, MaxActive = 3, Description = "..." },
},
DailyRewards = {
  AfkGraceSeconds = 90, ActivityMinimumStuds = 1, FlushIntervalSeconds = 60,
  Milestones = { {Minutes=5, Reward={Kind="Tokens",Amount=1}},
                 {Minutes=15, Reward={Kind="Item",Key="SpeedPotion",Amount=1}},
                 {Minutes=35, Reward={Kind="Item",Key="EntityShield",Amount=1}} },
  Wheel = { {Key="Token1",Weight=45,Label="1 Research Token",Reward={Kind="Tokens",Amount=1}},
            {Key="Token3",Weight=20,Label="3 Research Tokens",Reward={Kind="Tokens",Amount=3}},
            {Key="Potion1",Weight=20,Label="1 Speed Potion",Reward={Kind="Item",Key="SpeedPotion",Amount=1}},
            {Key="Potion2",Weight=5,Label="2 Speed Potions",Reward={Kind="Item",Key="SpeedPotion",Amount=2}},
            {Key="Shield1",Weight=10,Label="1 Entity Shield",Reward={Kind="Item",Key="EntityShield",Amount=1}} },
},
FieldNotes = { CompletionTitle = "FIELD ARCHIVIST" },
```
`Reward.Kind="Item", Key="EntityShield"` means `Protection.Charges += Amount`.

## Playtime accrual rules (A-SERVER)
Tick every 1 s per loaded player. A second counts when ALL hold: `InRound == true`,
`workspace.RoundActive == true`, `workspace.RoundLoadingState == "ready"`, `Escaped ~= true`,
`Level2_ExitTransition ~= true`, a living Humanoid with a HumanoidRootPart, and the player is
ACTIVE: moved >= ActivityMinimumStuds at some point in the last AfkGraceSeconds, OR
`Level3_Hiding == true`. Never subtract. Lobby and spectating never count (a dead body is not
a living humanoid). Accrue in memory; flush the delta into the profile through the existing
transaction path at most every FlushIntervalSeconds, on round end, before any claim/spin, and
on leave. Day roll: when `Daily.Day ~= today (UTC)`, reset PlaytimeSeconds/Claimed lazily inside
the transform (WheelDay is compared to today separately, so it needs no reset).

## Test rules (all agents)
Python + real luau at `LUAU_BIN=C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe`
(`luau-compile.exe` beside it). Follow `tools/tests/test_support_product_receipts.py` (extract
real blocks by string marker, fake DataStore/Players/task) and `test_round_entry_client.py`
(whole LocalScript under a fake DataModel). Every test file must run with
`python tools/tests/<file>.py` and print its check count. Static string-matching is not
runtime proof. Every touched .lua must pass `luau-compile.exe --binary <file>` (write to a temp).
Roblox type semantics differ from your fake (Color3 has no arithmetic; CFrame/Vector3 do): keep
fakes honest.

## Reporting
Each agent writes `artifacts/trello-20260916/agent-<id>-report.md`: files touched (exact
paths), what is verified offline and HOW, what is NOT verified (needs Studio), open questions,
texture/artwork needs (dimensions + use) for Codex, and the Trello card text draft.
