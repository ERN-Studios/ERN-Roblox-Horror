# Analytics schema — 2026-09-21

Trello **P1 · Før større ads: mål frafald fra join til første genstart**, plus
the shop measurement that hangs off the same module.

Everything is `ServerScriptService.ZyntraAnalytics` (ModuleScript) on Roblox's
`AnalyticsService`. No new remote, no new DataStore field, no new framework. The
hooks in the existing flows are one line each.

> **No ad spend or budget change is part of this work.** This only builds the
> measurement the spend decision would need.

---

## 1. What the API actually allows

Checked against the docs on 2026-09-21
([AnalyticsService](https://create.roblox.com/docs/reference/engine/classes/AnalyticsService),
[funnel events](https://create.roblox.com/docs/production/analytics/funnel-events),
[custom events](https://create.roblox.com/docs/production/analytics/custom-events),
[AnalyticsCustomFieldKeys](https://create.roblox.com/docs/reference/engine/enums/AnalyticsCustomFieldKeys)).
Every one of these shaped the code:

| Fact | Consequence here |
|---|---|
| `LogOnboardingFunnelStepEvent(player, step, stepName, customFields)` | the once-per-user funnel; no session id, so Roblox owns the dedup |
| `LogFunnelStepEvent(player, funnelName, funnelSessionId, step, stepName, customFields)` | the recurring funnel |
| `LogCustomEvent(player, eventName, value, customFields)` | everything else |
| `LogEconomyEvent(player, flowType, currencyType, amount, endingBalance, transactionType, itemSku, customFields)` | **not used** — see §7 |
| `customFields` is keyed by `Enum.AnalyticsCustomFieldKeys.CustomField01..03` | exactly **three** slots per event, spent deliberately below |
| Events are accepted from the **server** of a **published** place only; Studio and clients are refused | the Studio guard in §6 |
| Logging a funnel step marks every **earlier** step complete | steps are only ever logged forward, never backwards (§3) |
| Only the **first** instance of a step counts | replays are harmless; the per-server latch keeps them off the wire anyway |
| Only the **10 most recent** `funnelSessionId` values per user per funnel are kept | the retry funnel's session id is per lobby loop, so a player has to loop 11 times to lose the oldest |
| At most **100 unique custom event names** per experience | 9 names are used |
| Up to 10 funnels show on the dashboard | 2 are used |
| The rate limit is **not documented** (the engine only says "You have sent too many events") | a self-imposed 120 events / 60 s per server, with drop counting (§6) |

---

## 2. Call sites — file : function : line

Line numbers are at commit time; the function name is the durable anchor.

| Event | File | Function | Line |
|---|---|---|---|
| `Join` | `ServerScriptService/GameManager.Script.lua` | `setupPlayer` | 1024 |
| `Ready` | `ServerScriptService/GameManager.Script.lua` | `status.OnServerEvent` → `entryready`, **after** `activeEntry:Acknowledge` returned true | 1309 |
| `Leave` | `ServerScriptService/GameManager.Script.lua` | `Players.PlayerRemoving` (the file-level one) | 1333 |
| `Death` | `ServerScriptService/GameManager.Script.lua` | `playRound` → `hookLife` → `hum.Died` | 2408 |
| `Outcome "left"` | `ServerScriptService/GameManager.Script.lua` | `playRound` → `handleLeaveRoundRequest` | 2641 |
| `RoundStart` | `ServerScriptService/GameManager.Script.lua` | `playRound`, next to `roundStartedAt` | 2735 |
| `Outcome escaped/died` | `ServerScriptService/GameManager.Script.lua` | `playRound`, the end-of-round participant loop | 2793 |
| `Launch` | `ServerScriptService/GameManager.Script.lua` | `launchStation`, only after `TeleportAsync` succeeded | 2968 |
| `Objective` | `ServerScriptService/TeamObjectives.ModuleScript.lua` | `TeamObjectives.Announce` | 14 |
| `ItemUse "EntityShield"` | `ServerScriptService/ZyntraMonetization.Script.lua` | `handleProtectionAction`, outcome `Consumed` | 1593 |
| `ProfileLoaded` | `ServerScriptService/ZyntraMonetization.Script.lua` | `loadProfile`, after `ZyntraProfileLoaded = true` | 1949 |
| `ItemUse "Reentry"` | `ServerScriptService/ZyntraMonetization.Script.lua` | `useReentry`, respawn accepted | 2619 |
| `ItemUse "SpeedPotion"` | `ServerScriptService/ZyntraMonetization.Script.lua` | `useSpeedPotion`, after the consume committed | 3048 |
| `ItemUse` (RouteMarker, any stored item) | `ServerScriptService/ZyntraMonetization.Script.lua` | `inventoryFunction.OnInvoke` → `Consume`, after the write committed | 3255 |
| `ShopView` | `ServerScriptService/ZyntraMonetization.Script.lua` | `actionRemote.OnServerEvent` → `ShopView` | 3380 |
| `Purchase` (game pass) | `ServerScriptService/ZyntraMonetization.Script.lua` | `MarketplaceService.PromptGamePassPurchaseFinished`, `purchased == true` | 3542 |
| `Purchase` (developer product) | `ServerScriptService/ZyntraMonetization.Script.lua` | `MarketplaceService.ProcessReceipt`, **only** on `changed` (first-time grant) | 3657 |
| `ItemUse "DetectorScan"` | `ServerScriptService/ZyntraDetectorService.Script.lua` | `remote.OnServerEvent`, after the reading was granted | 35 |
| view / demo report | `StarterPlayer/StarterPlayerScripts/Shop Display Client.LocalScript.lua` | `setShown` (564), `startShownDemo` (594) | 42, 564, 594 |

**Why these and not others.** Each one is the authoritative *server* event, not
a client claim:

- `Ready` fires only when `Round Loading Runtime`'s `attempt:Acknowledge`
  **returned true** — it validates the token, the character, the level and the
  player's presence. The client's `entryready` alone is never enough.
- `Objective` is on `TeamObjectives.Announce`, the one choke point all three
  levels' objective controllers go through after a server-side validation
  (`canUsePrompt`, `canUsePump`, the Level 3 CD insert). It attributes to the
  **actor only**: every caller passes `player.Name`, and names are unique in a
  server, so `Players:FindFirstChild(actorName)` is the actor.
- `Purchase` for a developer product is inside `ProcessReceipt`'s `changed`
  branch — the same first-time-grant condition `PurchaseAlerts.Notify` uses —
  so a Roblox receipt retry never double-counts. For a game pass it is
  `PromptGamePassPurchaseFinished` with `purchased == true`, which is Roblox
  confirming the payment; a pass cannot be bought twice.
- `Launch` is in `launchStation`'s success branch, after `TeleportAsync`
  returned without error. A failed launch is not an attempt.

**Not measured:** the focused-torch toggle. It is a client-local flashlight
mode with no server-visible state, so there is nothing authoritative to hook.

---

## 3. The onboarding funnel (once per user)

`LogOnboardingFunnelStepEvent`, steps 1–6:

| Step | `stepName` | Logged from |
|---|---|---|
| 1 | `Joined` | `Analytics.Join` |
| 2 | `ProfileLoaded` | `Analytics.ProfileLoaded` |
| 3 | `RoundLoaded` | `Analytics.Ready` |
| 4 | `RoundStarted` | `Analytics.RoundStart` |
| 5 | `FirstObjective` | `Analytics.Objective` |
| 6 | `FirstEscape` | `Analytics.Outcome`, escaped only |

Custom fields on every step: **CF01** level tag, **CF02** origin, **CF03**
platform.

**Ordering.** The module keeps a per-player furthest-step latch and refuses any
step `<=` it, so a step is never logged twice and the funnel never goes
backwards. A forward **jump** is allowed on purpose: a reserved round server
never saw steps 1–2, the player genuinely did them in the lobby, and Roblox
completing them from step 3 is the correct answer.

**One known inflation.** Step 5 is completed by that same back-fill for a player
who escapes without ever personally announcing an objective (a passenger on a
team clear). Read step 5's *direct* count from the custom event
`zq_objective_first` instead; the funnel's step-5 number is an upper bound.

**Why no DataStore field.** `LogOnboardingFunnelStepEvent` has no session id:
it *is* Roblox's per-user lifetime funnel and it takes only the first instance
of each step for that user, forever. That is exactly the dedup a persisted
"furthest step" would have provided, so persisting one would add a DataStore
write path for nothing. In-memory dedup per server is the only thing we owe it,
and at most six onboarding calls per player per server is well inside the rate
budget.

---

## 4. The retry funnel (recurring) — the card's actual question

`LogFunnelStepEvent`, funnel name `ZQRetry`,
`funnelSessionId = "<JobId>:<UserId>:<loop>"`.

| Step | `stepName` | Meaning |
|---|---|---|
| 1 | `BackInLobby` | this player's round has ended and they are somewhere another one can be started |
| 2 | `StartedAgain` | they launched another round |

Custom fields: **CF01** level, **CF02** `afterdeath` / `afterclear` /
`unknown`, **CF03** platform.

**Where it opens.** Only on a server that can also observe the next launch —
otherwise every reserved round server would log a funnel session nobody could
ever finish and the dashboard would read 100% drop-off. In practice:

- **Published:** the round runs on a reserved server (`RESERVED` true), which
  stands down entirely. The public lobby opens the loop in `Analytics.Join`
  when the arrival came from our own place.
- **Studio / local-lobby fallback:** the same server runs both, so
  `Analytics.Outcome` opens it and `Analytics.Launch` closes it.

**A re-entry is never a retry.** Emergency Re-entry and the dev free respawn go
through `ServerStorage.ZyntraReentry` and never reach `playRound`, so
`Analytics.RoundStart` and `Analytics.Launch` never fire for them. Only a new
round can close the loop.

**CF02 is honest about what it cannot know.** Whether the previous round ended
in a death is only observable when the *same* server ran it, which is Studio and
the local-lobby fallback. On a published lobby the round ran elsewhere, so the
field reads `unknown`. Making it correct in production would need a field in the
`ReturnToLobby` teleport payload — a behaviour change in GameManager's transfer
path, deliberately out of scope here.

---

## 5. Custom events

Nine names. `value` is what the dashboard aggregates (count, sum, average,
min/max, per-user average).

| Event | `value` | CF01 | CF02 | CF03 |
|---|---|---|---|---|
| `zq_session_end` | seconds on this server | bucket | reached | entry |
| `zq_round_start` | 1 | level | origin | platform |
| `zq_round_outcome` | seconds in the round | level | outcome | origin |
| `zq_first_death` | seconds since the round started | level | cause | origin |
| `zq_objective_first` | seconds since the round started | level | origin | platform |
| `zq_round_relaunch` | seconds between the round ending and the next launch | level | afterdeath/afterclear/unknown | origin |
| `zq_shop_view` | 1 | product key | `card` / `demo` | origin |
| `zq_shop_purchase` | Robux actually paid | product key | `Utility` / `Donation` / `Pass` | origin |
| `zq_item_use` | 1 | item key | level | origin |

### Allowed values (the whole cardinality budget)

| Field | Values |
|---|---|
| level | `L0` (lobby / unknown), `L1`, `L2`, `L3` |
| origin | `new`, `returning`, `unknown` — from the profile's `firstLogin` at `ProfileLoaded` |
| entry | `new`, `returning`, `continued` — `continued` wins when this server presence began as a teleport from our own place |
| reached | `none`, `round`, `objective` |
| bucket | `lt60s`, `1to3m`, `3to10m`, `10m+` |
| outcome | `escaped`, `died`, `left`, `disconnected` |
| retry | `afterdeath`, `afterclear`, `unknown` |
| surface | `card`, `demo` |
| kind | `Utility`, `Donation`, `Pass` |
| item | `SpeedPotion`, `RouteMarker`, `EntityShield`, `Reentry`, `DetectorScan` |
| product | every key of `ZyntraConfig.Passes` / `.Products` / `.Donations` / `.Items` |
| platform | `PC`, `Phone`, `Tablet`, `Console`, `Unknown` |
| cause | see below |
| anything else | `other` (and `none` for a nil) |

Every field value goes through one sanitiser against that list. A value that is
not in it reads `other`, which is what bounds cardinality no matter what a
caller — including a client — passes.

**Death cause** is the exception, because another engineer owns the
`LastDeathCause` player attribute and this module must not constrain its
vocabulary. It is read defensively (`nil` → `unknown`), lower-cased, capped at
24 characters, refused unless it matches `^[a-z0-9_]+$`, and a server admits at
most **12 distinct causes** before everything further reads `other`.

**Platform** reads the player attribute `ZyntraDeviceClass` and caps it to the
fixed enum. Nothing publishes that attribute today, so it reads `Unknown`
everywhere; Roblox's own OS/device breakdown is the interim segmentation and it
costs us no field slot. The day a client publishes the attribute this starts
answering, and a client that lies can only pick another name from the enum —
segmentation only, never a grant.

**Acquisition attribution** is not logged. The only documented server-side
signals are `GetJoinData().SourcePlaceId` (used for the session rule, below) and
`ReferredByPlayerId`; neither tells us which ad or surface a player came from.
Roblox's own acquisition report is the source for that. `LaunchData` is free
text and is never read.

**No PII.** No names, no user ids, no free text in any field. The user id
appears only in the Studio debug ring (§6), never on the wire.

---

## 6. Session, teleport and dedup rules

**A session here is one server presence, tagged with how it began.** A round
runs on a *reserved server of this same place*, so one play session is several
server joins: lobby → reserved round → lobby. `Player:GetJoinData()` is
server-trusted, and `SourcePlaceId == game.PlaceId` for every one of our own
teleports (the `launchStation` arrival packet out, `{ReturnToLobby = true}`
home). So:

> **Rule.** A player arriving with `SourcePlaceId == game.PlaceId`, or arriving
> on a reserved round server at all, is the **same session continuing** — never
> a new join. `zq_session_end` tags it `continued` in CF03.

Read a true session count as `zq_session_end` **filtered to CF03 ≠ continued**.
The Roblox dashboard's own session-time metric already spans teleports inside an
experience, so it stays the authority on total session length; our bucket is
server-presence time, which is what the join → first round question needs.

`reached` on a lobby-origin session is `none` or `round` (the lobby sees the
launch, not the objectives). `objective` only appears on a server that actually
ran a round. The cross-server view of "did this user ever reach an objective" is
the onboarding funnel, which is precisely what it is for.

**Rounds per session** is not a single field: rounds start on reserved servers
and the lobby they came from may not be the lobby they return to. Read it as
`zq_round_start` count ÷ unique users over the same window, alongside Roblox's
own session count.

**Dedup keys.** Per (user, funnel session, step): the onboarding latch is the
per-player furthest step; the retry funnel's key is
`"<JobId>:<UserId>:<loop>"`, unique per server and per lobby loop.
`zq_first_death` and `zq_objective_first` fire once per session.
`zq_round_outcome` fires once per round (the round timestamp is cleared by the
first one that settles it).

**Studio guard.** `RunService:IsStudio()` or `PlaceId == 0` means the service
would refuse the event anyway, so it is never called. Everything is still
counted and written to a bounded 24-entry ring — see §8 for reading it.

**Rate limiter.** One sliding window for the whole server: 120 events per 60
seconds, dropped (not queued) past that, with a drop counter on the readback. A
full six-player round produces roughly 40 events, so the ceiling is an order of
magnitude clear of normal play. Marked `-- ponytail:` in the module, with
per-player buckets named as the upgrade if one player is ever shown to starve
the rest.

**Safety.** Every public entry point is a `pcall` boundary, nothing in the
module yields, and it neither reads nor writes a DataStore. The one call that
can throw (`AnalyticsService`) is separately pcall'd and counted. In
`ZyntraMonetization` the module is *optional by construction* — `FindFirstChild`
plus a pcall'd require, like `PurchaseAlerts` two lines above — so a place
without it still loads and every call site is guarded.

---

## 7. Shop measurement

- **VIEW and DEMO** are the only two facts the server cannot observe for
  itself, so the client reports them — through **one** new action on the
  existing `ZyntraAction` remote, `"ShopView" {Key, Demo}`. It grants nothing,
  answers nothing and prompts nothing. The server drops any key that is not in
  `ZyntraConfig`, requires a loaded session, is lobby-only
  (`InRound ~= true`), and sits behind the remote's existing shared per-action
  window. Demos still start no payment and grant nothing.
- **PURCHASE** is logged only after the authoritative grant (§2). Never when a
  prompt opens.
- **USE** is `zq_item_use`: speed potion, shield charge, re-entry, any stored
  item consumed through `ZyntraInventory` (route markers), and a granted
  detector scan.

`LogEconomyEvent` is deliberately **not** used. Research Tokens are a soft
currency whose balance lives on the profile, and an economy event wants a
trustworthy `endingBalance` at the moment of the flow; the sites above are not
all inside the transaction that produced the new balance. Sink/source reporting
is a second pass, inside `mutate`, if the dashboard's economy view is ever
wanted.

---

## 8. Verifying it

### In Studio (proves the wiring, **nothing** about the dashboard)

Studio can never deliver an event. What a play session can prove is that the
hooks fire, in order, with the right fields. `require` from a probe gets a
*separate module instance*, so the readback is published as attributes on
`ServerStorage.ZyntraAnalyticsDebug`:

| Attribute | Meaning |
|---|---|
| `Mode` | `studio` or `live` |
| `Logged` | events accepted by the rate limiter |
| `Dropped` | events the rate limiter refused |
| `Failed` | `AnalyticsService` calls that threw (always 0 in Studio) |
| `Faults` | throws inside the module itself — **must stay 0** |
| `Last` | the most recent record |
| `Recent` | the last 24 records, newline separated |

Probe recipe (a play session, Server context):

```lua
local folder = game:GetService("ServerStorage"):FindFirstChild("ZyntraAnalyticsDebug")
return {
  Mode = folder:GetAttribute("Mode"),
  Logged = folder:GetAttribute("Logged"),
  Dropped = folder:GetAttribute("Dropped"),
  Faults = folder:GetAttribute("Faults"),
  Recent = folder:GetAttribute("Recent"),
}
```

Start a round with the usual station recipe. `Recent` should show, in order:
`onboard 1 Joined`, `onboard 2 ProfileLoaded`, `onboard 3 RoundLoaded`,
`onboard 4 RoundStarted`, `zq_round_start`, then whatever the round does.
`Faults` must be 0 throughout.

### After the next published release (the only proof of reception)

1. Publish, then play a full loop on a **live** server: join → queue → round →
   die → back to lobby → queue again → escape.
2. Creator Dashboard → Analytics. Events can take a while to appear; check the
   next day before concluding anything is missing.
3. Confirm: the **Onboarding funnel** shows six named steps; **ZQRetry** appears
   under Funnels with `BackInLobby` → `StartedAgain`; all nine `zq_*` names are
   listed under Custom Events with populated CF01–CF03 breakdowns.
4. If a custom event is missing, check that the place is published and that the
   event came from a server — those are the two documented reasons for silence.

---

## 9. Reading the funnel

### Counts and conversion

For a week's data, per step of the onboarding funnel: unique users, conversion
from the previous step, and conversion from step 1. The **three biggest drops**
are the whole read-out — name them, and attach the matching custom event so a
drop has a cause, not just a number:

| Drop | What to look at |
|---|---|
| 1 → 2 (join → profile) | should be near 100%. Anything else is a DataStore or load fault, not a design problem. |
| 2 → 4 (lobby → round started) | the card's headline. Cross-check `zq_session_end` with CF03 ≠ `continued` and CF02 = `none`: those are the players who joined and never started a round, with their session-length bucket. If most sit in `lt60s`, the lobby never got them; if they sit in `3to10m`, they tried and something stopped them. |
| 4 → 5/6 (round started → objective / escape) | cross-check `zq_first_death` (seconds since round start, by level and cause) and `zq_round_outcome` (share escaped / died / left / disconnected, by level). |

### Times

- `zq_session_end` — average and distribution of the four buckets, split by
  `entry` and by `reached`.
- `zq_first_death` — average seconds into a round, per level and per cause.
- `zq_round_outcome` — average round length, per level and per outcome.
- `zq_round_relaunch` — average seconds between a round ending and the next
  launch; the retry funnel's conversion is the share who ever did.

### Shop

`zq_shop_view` (by product, card vs demo) → `zq_shop_purchase` (by product) is
the view→buy rate per product. `zq_item_use` against `zq_shop_purchase` says
whether what people buy is what they actually use.

### Before larger ad spend

None of this is a spend decision. The spend decision needs, in addition:

- **≥ 1 week of comparable data** on one stable build — a release mid-window
  makes the two halves incomparable.
- **Mature D1/D7 cohorts** — a D7 number needs cohorts that are at least seven
  days old, so the first usable D7 read is two weeks after the release.
- **CPP** (cost per play/install) from the ad platform, against the retention
  and monetisation the events above measure.
- **Source split** — organic vs paid, from Roblox's own acquisition report,
  because a blended retention number moves with the mix and not with the game.

Reference points, stated plainly:

- **15 Sept figures are historical:** 7.6 min average session, D1 3.76%,
  D7 0.02%. They describe the build that was live then, not this one.
- **10–12 min session and D1 6–8% are internal working targets**, not
  commitments and not benchmarks from anywhere else.

---

## 10. Tests

`tools/tests/test_zyntra_analytics.py` runs the real module under real Luau
against a fake `AnalyticsService` and the real `ZyntraConfig`: ordered
onboarding steps that never skip or duplicate, a death before an objective that
does not advance the funnel, a retry counted only for a new round (and never for
a re-entry), a teleport continuation that does not read as a second session,
unknown product keys and rate-limit overflow dropped, a throwing or
method-less service that never propagates, and every emitted custom-field value
inside the allow-list.
