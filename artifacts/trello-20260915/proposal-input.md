# Proposal input for Codex — game-specific constraints for #83 / #84 / #85 / #89 / #88-new

Written by the Fable 5.1 lead from the current source (2026-09-15, 22:20). Facts, not
decisions. Codex owns the proposal (`FORSLAG-TIL-MORGEN.md`); the owner decides tomorrow.
Nothing here is implemented.

## 1. Economy as it exists in code (`ReplicatedStorage/ZyntraConfig`)

| Source / sink | Value | Note |
|---|---|---|
| Level clear | +2 tokens (`LevelCompletionTokens`) | the only earned source today |
| Supporter pass | 99 R$, +10 tokens once, tag | |
| Tokens4 | 49 R$ → 12.25 R$ per token | |
| Tokens20 | 149 R$ → 7.45 R$ per token | the marginal price of a token |
| Stamina / Battery upgrade | 1 token = +5 % permanent | **no level cap in the code** — `normalizeProfile` clamps to ≥ 0 only |
| Entity Shield | 5 tokens = one stored 5 s charge | consumable, the only repeatable sink |
| Emergency Re-entry | 29 R$ (Robux only) | not a token item |
| Studio | `StartingTokens = 25`, `GrantAllPasses` | test only, never in production |

Implications for the proposal:
- Every free token is worth 7–12 R$ of Tokens20/Tokens4 sales. Codex's 2.30 tokens per
  active day ≈ 17–28 R$/day of product value; over 30 active days ≈ 69 tokens ≈ 3.5
  Tokens20 packs. Say so explicitly and let the owner pick the number; a cheaper
  variant is 1 token at the 5-minute milestone and cosmetics/stamps above it.
- Because upgrades are uncapped, free tokens compound into permanent +5 % steps. A
  first-release cap (e.g. 10 levels each, i.e. +50 %) would need an owner decision AND a
  migration rule for players already above it (do not remove what they bought).
- Tokens are Robux-purchasable, so ANY random reward that costs tokens (or Robux) is a
  *paid random item* under Roblox policy. A wheel must be free to spin (no token/Robux
  entry, no purchasable extra spins) to stay outside that regime; publish odds anyway.

## 2. Persistence contract (`ServerScriptService/ZyntraMonetization`)

- Profile lives in DataStore `ZyntraPlayerData_v1`, schema `Version = 4`, normalised by
  `normalizeProfile`: every field is rebuilt from a KNOWN key set, so a new feature adds
  its fields there with validation (clamp numbers, whitelist string keys, drop unknowns).
  Additive only; never bump semantics of existing fields.
- One-time markers already have two idioms: `Grants.<Key> = true` (feedback gift) and the
  per-row/per-source markers `SalesImport.Sources/Rows` being added tonight for #36. A
  daily claim fits the same shape: `Rewards.Daily[<UTC day string>] = true`,
  `Rewards.Playtime[<UTC day>] = {Seconds = n, Claimed = {["5"]=true, ...}}`. Idempotent
  per key ⇒ safe across servers and retries.
- Write discipline: a transform that returns `false` CANCELS `UpdateAsync` (never mutate
  `current` and then return false); the session copy adopts what the callback read;
  write-bearing `ZyntraAction`s have a 1 s per-action window (`WRITE_ACTION_WINDOW`), read
  actions 0.12 s; settings writes sit behind escalating floors. A playtime accumulator must
  batch (write every ~60–120 s and on leave), not per second, and must never starve the
  settings/mute queue.
- Studio never writes DataStores (`RunService:IsStudio()` guard everywhere); Studio API
  access is disabled, so live stores cannot be read from Studio either. Test with the
  offline luau harness (`tools/tests/test_feedback_gift.py` is the template) plus a Studio
  play session for UI.
- Client-visible state is published as read-only player attributes (pattern:
  `ZyntraReentryCredits/Price/ProductId`, `ZyntraProfileLoaded`); the client never trusts
  them for authorisation. A "next claim at" value should be a server epoch
  (`os.time()`), rendered by the client against `workspace:GetServerTimeNow()`.
- Day boundary: `os.time()` is UTC. "Daily" resets at 02:00 Danish summer time unless a
  fixed local reset hour is chosen — an owner-visible choice, state it in the proposal.

## 3. Playtime accounting — what the server can see

- Round membership is server-authoritative: `player:GetAttribute("InRound") == true` and
  `workspace:GetAttribute("RoundActive") == true` (lobby time is excluded by construction).
- Activity signals that exist server-side and are NOT client-trusted: character root
  displacement (Heartbeat sample), validated interactions (`canUsePrompt` in
  PuzzleManager, pump prompts in Level 2, CD deposits in Level 3), the Level 3 hiding
  state (`Level 3 Hiding Controller` owns it; a hidden player is legitimately still).
  Client input events are NOT a safe activity source (spoofable, and touch/gamepad differ).
- Suggested rule (server): a minute counts if, within the last 60 s, the root moved
  ≥ N studs cumulatively OR a validated interaction happened OR the player is server-hidden
  under a table. Never subtract earned time. Cap accrual at the round's wall time.
- Spectating (dead/escaped) is `Spectating` client-local; the server knows death via
  `alive[player]` in GameManager. Decide whether spectating counts (I would not).

## 4. UI limits that shape the "Daily Rewards" tab (#89)

- The Zyntra terminal (`ZyntraStore.LocalScript.lua`, 3.2 k lines) is lobby-only (its
  opener stands down in rounds). Tabs are built in-file; a new tab must pass
  `UIRegression.Compact("ZyntraTerminalFitMatrix")` (1405 checks over 11 phone/tablet/
  desktop layouts) and every stood-down caption it shows ("CLAIMED", "IN 3H 12M",
  "TOMORROW") must be listed in `Fit.ZyntraDisabledCaptions`, else the matrix fails.
  Fit tiers: phone = `fit.Compact and fit.Touch`, tablet = `fit.Touch`, pointer.
- `RoundUI` is at Luau's 200-register limit: in-round HUD state must live in a `do ... end`
  block. Keep in-round reward UI to one line of text or nothing; claims belong in the lobby.
- `ReduceFlashing` (profile setting = player attribute) must turn any wheel spin into a
  slow cosine motion with no strobe; `ReduceCameraShake` is irrelevant here.
- The shop wall being built tonight (#88, `LobbyShopDisplay`) has pedestals per existing
  catalogue item and a plate/prompt → detail card flow; a "supply crate" pedestal for the
  daily reward would reuse that exact interaction if the owner wants the reward physical.

## 5. Speed Boost Potion (#85) — engine constraints

- `Humanoid.WalkSpeed` has multiple writers: NoiseReporter (client sprint 16 → 26, the
  one definition of "asking to sprint"), RoundUI, Level 2 Slide Controller, Level 3 Hiding
  Controller, EntityKill/EntityAI. A potion must be applied as a server-published
  multiplier attribute (e.g. `ZyntraSpeedBoost = 1.10` until epoch T) that every writer
  multiplies in, otherwise the next sprint toggle overwrites it. Stamina is client-local;
  the potion must not touch it.
- Chase margins today: Pool Slide EnragedSpeed 32 / NormalRunSpeed 20 vs sprint 26; the
  Level 3 finale hall speed is fixed from the runner's lead (tuned 2026-09-14 for a tight
  escape). +10 % for 6 s once per round (Codex) is inside those margins; anything longer
  or stackable must be re-measured in all three levels before release.
- Consumables need the same inventory idiom as Entity Shield (`Protection.Charges` with a
  `Revision`), an activation `ZyntraAction` under the 1 s window, and a per-round latch.

## 6. Anti-abuse and ops

- All claims via the existing `ZyntraAction` remote (server validates day key, profile
  loaded, cooldown); reject when `ZyntraProfileLoaded ~= true`.
- Dev tooling: `DevAccess` whitelist + a DEV row (Studio-only "advance day") for QA; add
  its captions to `Fit.ZyntraDisabledCaptions`.
- No analytics pipeline exists in the game; D1/D7 come from the Creator Dashboard only.
  `PurchaseAlerts` (#69) is unrelated and deferred.

## 7. Horror fit (lead's view, for Codex to weigh)

Rewards should never interrupt a round: claim in the lobby, one quiet HUD line at most in
rounds. Cosmetics must not glow enough to break the darkness (token research already
says so). A daily "Zyntra supply" reads as in-fiction dispatch equipment; a casino wheel
does not — if a wheel stays, style it as a Zyntra supply selector with subdued motion.

## Open owner questions to surface tomorrow

1. Free-token budget per active day (0.5 / 1 / 2.3).
2. Upgrade level cap: none (today) vs a cap with grandfathering.
3. Daily reset: UTC midnight (02:00 DK) vs fixed local hour.
4. Wheel: free only (recommended) vs any paid entry (policy work).
5. Physical daily-supply pedestal on the new shop wall: yes/no.
