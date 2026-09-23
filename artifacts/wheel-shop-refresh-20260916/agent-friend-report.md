# A-FRIEND — Friend Boost (contract section 4)

Status: implemented, offline-verified, **not installed in Studio** (agents do not touch
Studio, the manifest or git).

## Files

| File | Change |
|---|---|
| `ServerScriptService/FriendBoost.ModuleScript.lua` | **NEW** (142 lines). Friendship cache, the two lobby attributes, `Start` / `PrimeRoster` / `CountRoundFriends`. |
| `StarterPlayer/StarterPlayerScripts/Friend Boost Client.LocalScript.lua` | **NEW** (154 lines). The lobby chip and the invite button. |
| `ServerScriptService/GameManager.Script.lua` | **4 call sites, 15 lines incl. comments.** require + `Start()` at boot (after the `Round Loading Runtime` require); `PrimeRoster(participants)` at the top of `playRound`; `PrimeRoster` after a successful re-entry; the third argument on `zyntraLevelCompleted:Fire`. |
| `ServerScriptService/ZyntraMonetization.Script.lua` | `FriendBoostTenths` default, normalisation, snapshot field, and the payout inside the `levelCompletedEvent` handler. Nothing else. |
| `ReplicatedStorage/ZyntraConfig.ModuleScript.lua` | `FriendBoost = {PercentPerFriend = 10}` and its comment. Nothing else. |
| `tools/tests/test_friend_boost.py` | **NEW.** 318 checks. |

No other file was touched. RoundUI, UIDevice, UIStyle, UIRegression and the round loop are untouched.

## The documented interpretation

Stated in full in the module header, because the owner's wording
("a friend you invited and play with") has no direct implementation here:

> The project has **no invite or referral tracking**. `SocialService:PromptGameInvite`
> fires and forgets, Roblox reports no join source into the round, and the queue
> stations track a party's *members*, not how anyone heard about it. Inventing a
> referral system was ruled out, so the criterion is the brief's own fallback:
> **a verified Roblox friend (`Player:IsFriendsWith`, server-side, pcall'd) who was a
> participant of the SAME round on the SAME server.**

Being friends and online elsewhere pays nothing. Being on this server but not in the
round pays nothing — the roster GameManager hands over at completion is that round's
`participants` list, never `Players:GetPlayers()`.

## The calculation

Base payout is `Config.LevelCompletionTokens` = 2. The boost is counted in **tenths of a
token**, and the unpaid fraction persists on the profile as `FriendBoostTenths` (0..9):

```
tenths = data.FriendBoostTenths + base * (friends * PercentPerFriend) / 10
bonus  = math.floor(tenths / 10)
data.FriendBoostTenths = tenths % 10
data.Tokens += base + bonus
```

2 tokens × 1 friend × 10% = **0.2 of a token = 2 tenths per clear**, so:

| Friends | Per clear | Over 5 clears | Check |
|---:|---|---|---|
| 0 | +0 | 10 tokens | unchanged behaviour |
| 1 | +2 tenths | 11 tokens (the whole token lands on the **5th** clear) | +10% of 10 |
| 2 | +4 tenths | 12 tokens (3rd and 5th) | +20% |
| 3 | +6 tenths | 13 tokens | +30% |
| 5 | +10 tenths | 15 tokens (**+1 every clear**, remainder always 0) | +100% |

Additive, no cap, self excluded, each friend once. The remainder is server-side only and
is never shown as tokens. Message: unchanged at 0 friends
(`+2 Zyntra Research Tokens for completing the level.`); with friends,
`+N Zyntra Research Tokens for completing the level (Friend Boost +X%).` where N is what
was actually paid.

**Nothing else multiplies completion tokens** — `Config.LevelCompletionTokens` has exactly
one live reader (verified by grep over the working tree; the only other hits are in
`.studio-push-backups/`). Purchases, the wheel, daily rewards, gifts and the historical
import are untouched.

## Verified offline

```
LUAU_BIN=.../codex-luau-0.737/luau.exe
python tools/tests/test_friend_boost.py   -> friend boost: 318 checks passed
python tools/tests/test_token_grants.py   -> token grants: 243 checks passed
```

All five touched `.lua` files compile with `luau-compile.exe --binary` (FriendBoost,
Friend Boost Client, GameManager, ZyntraMonetization, ZyntraConfig).

The suite runs three **real** sources under one fake DataModel: the whole FriendBoost
module (against fake Players whose `IsFriendsWith` is scripted and can throw), the whole
client LocalScript (with the real `UIStyle` and the real `ZyntraConfig`), and the payout
arithmetic extracted from ZyntraMonetization by string markers — the `levelCompletedEvent`
handler and the `FriendBoostTenths` normalisation lines. `ZyntraConfig` is loaded for real,
so `PercentPerFriend` is read and not restated.

Covered: 0/1/3 friends; self excluded (asserted on every lookup); one friend counted once;
an unordered pair costs one web call; join and leave both republish; a throwing lookup
counts 0 now, is **not** cached and resolves on the next pass, while a definitive answer
is cached; `CountRoundFriends` ignores a friend who is on the server but not in the
roster, dedupes by UserId, excludes self, and makes no web call at all (so it cannot yield
in the win loop); `PrimeRoster` warms exactly the party's pairs and is cheap to repeat;
the tenths normalisation over nil/0/5/9/10/-1/999/"4"/"nonsense"/4.7/NaN/inf; the payout
for 0/1/2/3/5/7 friends over several completions, a carried remainder across a session, a
replayed completion, and a garbage friend count (nil, -1, 1.7, NaN, ±inf, 1e9, "2") never
producing a non-finite balance; the chip's copy for 0/1/2 friends, live repaint, hostile
attributes, lobby-only visibility against all six screen-owning modals, invite gating
(yes / no / throwing service with retries), geometry on pointer and phone, 44 px targets,
11 px text floor, and that the script fires no remote and publishes no attribute.

I mutation-tested the suite: seven deliberate regressions (wrong `PercentPerFriend`,
dropping the bonus, dropping the remainder, caching a failed lookup, counting self,
singular/plural, sizing the chip from `rect.Height`) were **all** caught.

The other 16 offline suites that read GameManager or ZyntraMonetization still pass
(`test_daily_rewards`, `test_token_grants`, `test_feedback_gift`, `test_speed_potion`,
`test_support_product_receipts`, `test_lucky_wheel_client`, …).

## Needs Studio / needs the owner

1. **Install order matters.** `GameManager` now does
   `require(script.Parent:WaitForChild("FriendBoost"))`. If the ModuleScript is not in
   ServerScriptService when the new GameManager source lands, `WaitForChild` yields
   forever and **the whole game fails to boot**. Install
   `FriendBoost.ModuleScript.lua` with `tools/install_new_scripts.py` **before**
   pushing GameManager. (This matches the existing pattern for `Round Completion Routing`
   and `Round Loading Runtime`, which are required the same way.)
2. `Friend Boost Client.LocalScript.lua` is also new and needs installing +
   a manifest item.
3. Only a Studio/live pass can exercise: real Roblox friendships and their throttling,
   whether `SocialService:CanSendGameInviteAsync` answers on the platform under test
   (it is false in Studio on some builds — the button then simply does not draw), the
   real chip position and font metrics, and a real completion paying real tokens.
4. Suggested live check: two friended accounts, one round, both escape → both see
   `FRIEND BOOST +10%` in the lobby and `(Friend Boost +10%)` on the fifth clear.

## Decisions and deviations from the contract

* **`RegisterControlRect` + `TopRightPanel` would have fought each other, so the chip
  keeps a content height.** On touch, `TopRightPanel`'s height is *"the room above the
  registered control rects"* (`zones.Controls.Top - 8`). A panel that both registers
  itself and takes its height from that answer collapses to 0, stops being drawn, leaves
  the union, grows back, and oscillates forever through `scheduleControlRefresh`. The chip
  therefore takes **Left / Top / Width** from `TopRightPanel` — which on touch depend only
  on the safe area, never on the control zone — and sizes its own height from its content.
  The call and the registration are both there as the contract asks; a test asserts the
  chip does not shrink when a cluster is measured at the very top.
* **Residual, for the owner:** the contract's rationale for registering
  ("so touch controls dodge it") is inverted — `RegisterControlRect` makes *panels* dodge
  the registered rect, not controls. The one visible consequence is that while the chip is
  up in the lobby, anything else calling `TopRightPanel` there reads its height as ~0.
  Nothing in the plain lobby does today (the objective readouts are level HUDs, and the
  store's dev chip only exists while a screen-owning modal is open, which hides the chip).
  Say the word and I will drop the registration — it buys nothing measurable.
* **Friend count sanity bound instead of a bare `math.max(0, …)`.** The contract's snippet
  is NaN-safe by luck (`math.max(0, nan)` returns 0 in Luau) but not infinity-safe:
  `math.huge` would write a non-finite token balance. The handler now range-tests
  (`counted >= 0 and counted < 1e6`). **This is not a cap on the bonus** — the owner asked
  for none, and no real party approaches it; it only rejects a caller bug.
* **`PrimeRoster` is called once, in `playRound`.** Both launch paths (the Studio
  `launchStation` fallback and the reserved-server arrival) funnel through it, so one line
  covers "where a party launches" instead of two. Re-entry gets its own call as specified,
  which doubles as a retry for any pair whose lookup failed at launch.
* **`CountRoundFriends` never yields and never calls the web.** It reads the cache the
  background passes fill. An unresolved pair counts 0 — the boost can be missed, never
  invented — because the win loop runs between the last death and
  `runPostWinIntermission` and must not block there.
* Failed lookups are never cached, matching `stationAllowsPlayer`'s existing rule in
  GameManager, and the invite button follows the same discipline: a *thrown*
  `CanSendGameInviteAsync` is retried (3 attempts, 5 s apart) and only a definitive
  `false` (or three failures) hides it for the session.

## Open questions

* Should the chip stay up when the player has 0 friends on the server? It currently does,
  showing `FRIEND BOOST +0%` / `INVITE FRIENDS TO EARN +10% PER FRIEND`, which is what the
  contract specifies — but it is also the state most players are in most of the time.
* The chip says **"ON THIS SERVER"**, which is the honest reading of the published
  attributes, while the payout additionally requires being in the same round. A player
  with a friend in the lobby who then queues alone sees +10% and is paid +0%. Tightening
  the chip to the round would mean publishing a second, round-scoped pair of attributes;
  the contract asks for the lobby-only chip, so I left it.
* `FriendBoostTenths` is in the snapshot pushed to the client but no UI reads it.
