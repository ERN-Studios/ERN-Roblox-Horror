# Protection: root installation and native acceptance

**Delivered: v1840, mouse-published 2026-09-10 at 09:09:24.097/.146 Europe/Copenhagen. Combined independent score: 8/10.** Final normal-round cleanup, fixture removal, 125/125 compilation and 125 matched/0 drift source audit passed before publication. See [release journal](release-journal-v1840.md) and [combined review](final-functional-review.md).

The instructions and baseline descriptions below are the preserved preparation runbook, not a current pending installation. All 19 reviewed files are installed, including the three originally absent scripts. Do not replay creation or overwrite current sources from these historical baselines. Pricing and Trello Testing cards remain skipped by owner instruction; the focused implementation checks did not reopen those cards.

The machine-readable authority is **`install-manifest.json`**: all 19 exact target paths/classes, immutable reviewed proposal paths, raw/canonical SHA256, byte counts and the 16 current expected baselines. Current Developer code is the exact `a707c6ed…a3a03` mouse-published v1835 reported by root. Use merged Monetization **`1f44dfa34ef69fec7cf04be80007498a1945afde0422e2e099ec9a8675d53ef4`**, not the older standalone transaction proposal. If the PoolSlide bug fix changes a listed controller before integration, the baseline guard must reject it; merge only that file's protection delta onto the newly reviewed controller, retest and refresh this manifest explicitly.

Every listed baseline matched the current filesystem at preparation, and every normalized baseline matched the sync manifest. `baselineRawSHA256` is the file byte guard. `baselineCanonicalSHA256` uses the existing `studio_source_contract.normalize` convention (CRLF→LF); it is the Studio compare-and-swap baseline. Several original modules use CRLF, so these two hashes intentionally differ. Do not turn that difference into a forced overwrite or blanket newline exception.

## Exact scope and dependencies

There are **16 replacements + 3 creations**, taking the current script count from 122 to 125 if no other scripts are added meanwhile. The sync manifest also contains 14 RemoteEvents; no RemoteEvent is added by this feature. Existing `ZyntraAction`, `ZyntraGetProfile` and `ZyntraProfileChanged` are reused.

The complete replacement list is in the manifest. It consists of merged Monetization/Config; NoiseRegistry; L1 EntityAI, EntityKill, EntityAnimation, MazeGenerator and JumpscareUI; L2 Foam Controller, Foam Observer and Slide Controller; L3 Manager and Hiding Controller; and Store, UIDevice and UIRegression. No Objective, Music, Round Adapter, World Builder, PoolSlide rig/enable flag, account setting or animation asset is changed by this installation.

The three new production scripts are:

| Roblox path | Class | Exact proposal SHA256 |
| --- | --- | --- |
| `ServerScriptService.PlayerProtection` | ModuleScript | `da2e5ac8a2cc2a5ac3eec5e07179446035ac99a285f6af63c44c376269f9a522` |
| `ReplicatedStorage.ProtectionClient` | ModuleScript | `7465190a4b065cc0398923bfeb5938914e2cdfd7e06db574df25109a5c1d9649` |
| `StarterPlayer.StarterPlayerScripts.ProtectionHUD` | LocalScript | `a5e45e30921737fdae13d62e82faece8ba4eea2ed092b8e652b1bd6f0fc0de3a` |

Their exact destination filenames and absolute proposal paths are in the JSON. They are currently absent on disk and from the recorded sync manifest; native absence must still be checked before creation. The service runs on the server; the client module refuses server require. Install Config/UIDevice and the shared service/client before consumers. All source operations take place in stopped Edit, so runtime execution order does not depend on a partially applied batch.

## What the existing source tools actually support

- `tools/record_pending_push.py` scans known mirror entries, remembers their prior canonical Studio hash, and explicitly reports unknown new scripts as `UNKNOWN` with exit 1. It does not create manifest entries or instances.
- `tools/push_repo_to_studio.py` walks each existing path, refuses missing/wrong-class/conflicting sources in phase 1, then uses `ScriptEditorService:UpdateSourceAsync` with an in-callback baseline guard. It rereads and compiles the landed source. It cannot create the three missing instances. Do not use conflict-overwrite or skip-conflict flags to get a partial feature through.
- `tools/stage_push_payload.py` also requires every input to be a known manifest file. Its `.rbxmx` objects are source containers, not a new-script creation mechanism. A separate payload for the three new scripts is provided below. Its docstring mentions an old proxy outage; current proxy availability must be established by root's actual tool result, not assumed from that historic comment.
- `tools/record_synced_source.py` refuses unknown files. It updates only existing entries after a parity dump confirms class and canonical content. It cannot bootstrap new entries.
- Project `CLAUDE.md:179` prescribes creating new scripts through `execute_luau` + `UpdateSourceAsync`, then adding manifest entries with `sha256_of`/`canonical_bytes`. Source reads must use native `.Source`; `script_read` can return an old editor buffer. These are actual local tool contracts, not an additional user approval requirement.

## Edit installation sequence

1. Stop Play. Read the live sources/classes for all 16 existing entries and verify against the recorded canonical baselines. Check no native instance occupies any of the three new paths. Save the 16 source backups, current sync manifest and relevant native script Enabled/Disabled states. Recheck all proposal hashes and raw filesystem baselines from `install-manifest.json`; any mismatch is a rebase, not an overwrite.
2. Prepare the three new sources without adding fake synced entries. The supplied `production-new-sources.rbxmx` contains only three inert ModuleScript source containers. Root may copy it into the current Studio install's `content/ProtectionNewScripts/production-new-sources.rbxmx`; use the existing `studio_content_dir()` helper to resolve the installed content directory. This preparation did not copy anything there. Run **`install-new-scripts-edit.luau`** only in stopped Edit after verifying its payload. It checks all targets are absent, checks all three source lengths/fingerprints, compiles every complete body through a nonexecuted wrapper, creates the correct native classes, writes through UpdateSourceAsync and compares `.Source` exactly. Any failure removes only instances created by that invocation. It leaves the new ProtectionHUD **Disabled=true** until the rest of the batch is installed. No actual service module is required by the bootstrap.
3. Preserve the bootstrap JSON result and full native `.Source` readback for all three instances. Only after exact class/source/compile success, copy their reviewed sources into their normal repo destinations and add the three entries from `new-manifest-entries.candidate.json` to the real manifest. That file intentionally says `verification-required`; change each to `synced` only against the observed successful creation. Use canonical hashes/bytes, no invented `studioSha256Before`, and no trailing-newline flag unless a real permitted landing is explicitly observed. Recompute `counts.scripts` and `counts.total`; call the existing newline metadata helper. The candidate JSON is not itself a replacement for the real manifest.
4. Copy the 16 reviewed replacements into their repo paths after repeating their raw baseline guards. The recommended dependency order is the JSON `order`: Config/UIDevice/client/service first, then NoiseRegistry and the Hiding/Observer dependencies, AI/capture consumers, Monetization, Store and HUD. Preserve every pre-existing script's enable state; GameManager owns level-specific enablement. `record_pending_push.py --dry-run` should now report only the intended replacements and no unknown scripts. Then record pending pushes and run the normal audit. Run the real push only if every named replacement is ready/already applied. `--file` is a singular filter; use a scoped invocation per file if the global pending list contains another feature. Do not accidentally push unrelated pending work.
5. If the MCP proxy truly fails, use the already proven staged-payload transport for the 16 known files with all-target preflight, exact byte verification, safe wrapper compilation and UpdateSourceAsync. This is an alternative transport, not a reason to erase baseline checks. After it lands, use the native parity dump and `record_synced_source.py` to record the exact files. Do not use a full pull to paper over pending local changes.
6. Run the complete native compile/parity probes, now expecting 125 script entries if this was the only addition. Inspect the three new classes and names, and require exact source parity under the existing single-newline contract. After all 19 sources pass, set `StarterPlayer.StarterPlayerScripts.ProtectionHUD.Disabled=false` in Edit and read it back. Do not enable the L1 level scripts or PoolSlide through this feature. Do not start Play with an incomplete dependency batch.
7. Perform the native feature acceptance below. Stop Play afterward and confirm every fixture instance/run attribute is gone, all 19 production sources still match, no temporary compile modules remain and the HUD has its intended enabled state. Publish this feature once, using the mouse through File→Publish to Roblox, only after final critic acceptance and native checks. No publication was performed by this preparation.

## Isolated native profile: no real purchase or stored balance

This uses the current connected player's UserId as a key inside an **in-memory Play-only profile**, not a new Roblox account or a modification to that account's saved balance. It does not call Marketplace purchase prompts or fabricate paid receipts. The memory facade has no DataStoreService delegate. MarketplaceService itself is not stubbed; avoiding Robux prompts follows the explicit Protection Buy/Use-only test scope, not a technical global prompt block. Its badge facade refuses both lookup and award, and existing Studio receipt/MessagingService guards remain unchanged. The scoped runtime search found persistent DataStore operations only in Monetization; GameManager's separate cohort MemoryStore write has its existing `IS_STUDIO` early return.

Use a fresh normal Play server after all production sources are installed in Edit. Their first native requires must see the final Config/service/client identities; changing a cached ModuleScript's Source does not reload it. Do not enable Studio API access. The real production Monetization stays on its existing nonpersistent Studio branch until its Play copy is replaced.

Copy `play-fixture-sources.rbxmx` to the same staged content folder when needed. It contains inert `Memory` and `Monetization` source containers for the already reviewed fixture. Exact expected files/hashes:

- Play `ServerScriptService.ProtectionNativeMemoryProfiles`, ModuleScript ← `../native-fixture/MemoryProfiles.ModuleScript.lua`, SHA `2e3c6fdfc7cac6df485d9071e283c4f3aa114ecb0c729a61aee8803ee87c35b0`.
- Play `ServerScriptService.ProtectionMonetizationNativeFixture`, disabled Script ← `../native-fixture/Monetization.NativeFixture.Script.lua`, SHA `92f78aae8fa45dbf96348d7fe651f8747eff7fb4271b70a49765fd6593bcbb82`.
- Its input is the exact merged production source `1f44dfa3…3ef4`; `../native-fixture/source-manifest.json` and the hash-named input snapshot prove the transform. These two fixture instances never go in Edit, the runtime mirror or the production sync manifest.

Before the fixture module's first require, run this **server-side in Play**:

```lua
local rs = game:GetService("RunService")
assert(rs:IsStudio() and rs:IsRunning() and rs:IsServer())
local runId = game:GetService("HttpService"):GenerateGUID(false)
workspace:SetAttribute("ProtectionNativeFixtureRunId", runId)
workspace:SetAttribute("ProtectionNativeFixtureTokens", 5)
workspace:SetAttribute("ProtectionNativeFixtureCharges", 2)
return runId
```

Create the memory ModuleScript and the disabled fixture Script at the paths above, and set both Sources through UpdateSourceAsync from the verified payload. Set the fixture Script's own `ProtectionNativeFixtureRunId` attribute to the same run ID. Compile the complete sources without executing their bodies. **Destroy only the original Play-copy `ServerScriptService.ZyntraMonetization` before enabling the fixture Script.** Merely disabling it or replacing its Source is insufficient isolation. The fixture's Bind explicitly refuses an extant original or a different live fixture owner. Then set the fixture Script Disabled=false. If bootstrap fails after that swap, stop Play and start fresh from the unchanged Edit sources; do not improvise another live owner.

The normal server Script, not `execute_luau`'s separate require cache, creates `ServerStorage.ProtectionNativeFixtureProbe`. Use that BindableFunction for private service observations. Existing installed clients can consume its new profile nonce through the ordinary profile event; do not duplicate their input connections by blindly cloning Store/HUD. If a client must be restarted, retire its old script/GUI/handlers and verify one intended command before continuing. Wait for initial profile/pass refresh to settle; the seed's token grants are marked already applied only to keep test balances stable, and both Robux history streams begin at zero.

```lua
local probe = assert(game.ServerStorage:FindFirstChild("ProtectionNativeFixtureProbe"))
local player = assert(game.Players:GetPlayers()[1])
local config = require(game.ReplicatedStorage.ZyntraConfig) -- immutable config only
local key = "u_" .. tostring(player.UserId)
local before = probe:Invoke("Inspect", player.UserId)
assert(before.Profile and before.Profile.Tokens == 5)
assert(before.Profile.Protection.Charges == 2 and before.Active == false)
probe:Invoke("ClearFaults")
probe:Invoke("ResetCounters")
return game:GetService("HttpService"):JSONEncode(before)
```

Inspect supports negative Studio test UserIds. There is no arbitrary profile-set command. For a fresh four-token/zero-charge case, stop Play and rearm the next fresh memory module with seeds 4 and 0; changing attributes after module require does not change its captured seed. A same-Play owner restart deliberately preserves memory and is a recovery test, not a reset.

## Native commands and observations

Use the real Store card and HUD input for Buy/Use. Never invoke ProcessReceipt or PromptProductPurchase for these tests. `Inspect` reports Profile, Now, private Active, displayed ExpiresAt and Health from the game module cache. `Snapshot` reports memory writes/callbacks and their timed events. Save JSON with bounded chunks when large; do not infer success from truncated tool output.

```lua
-- Select ONE fault case per run, after initial profile/pass refresh settles.
local probe = assert(game.ServerStorage:FindFirstChild("ProtectionNativeFixtureProbe"))
local player = assert(game.Players:GetPlayers()[1])
local config = require(game.ReplicatedStorage.ZyntraConfig)
local key = "u_" .. tostring(player.UserId)
local case = "delay-reserve" -- or "lost-response", "lost-finalize", "callback-conflict"
assert(case == "delay-reserve" or case == "lost-response"
    or case == "lost-finalize" or case == "callback-conflict")
probe:Invoke("ClearFaults")
if case == "delay-reserve" then
    -- Before a real HUD use: reserve waits ten seconds, with no early effect.
    probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key, DelaySeconds=10})
elseif case == "callback-conflict" then
    probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key, ConflictTokenDelta=7})
else
    -- An empty reserve fault lets reserve commit normally before finalize loss.
    if case == "lost-finalize" then
        probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key})
    end
    probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key, FailAfter=true})
    probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key, FailBefore=true})
    probe:Invoke("QueueFault", {Store=config.DataStoreName, Key=key, FailBefore=true})
end
return game:GetService("HttpService"):JSONEncode(probe:Invoke("Snapshot"))
```

Each selector value is a **separate case**, never one combined queue. A fault targets the next matching profile UpdateAsync; pass refresh or other same-key work may consume it. Verify the actual Begin/Committed/ResponseLost event order before naming the failed stage. The HUD's Retry must retain the exact SessionNonce, Revision and RequestNonce. Finalize retry must not call Activate again, refresh ExpiresAt or refund a locally known successful effect. For controlled cancellation use `probe:Invoke("ClearProtection", player.UserId)`; it does not heal or change balance.

Minimum combined acceptance: five tokens buy one stored charge; four tokens refuse; one use starts a full five seconds **after** durable reservation; exact expiry does not extend under retry; ending/changing the round or character during delayed reserve prevents activation and refunds once. Validate death/escape/lobby/loading/modal gates, live capture availability, actual keyboard/touch/controller input and seven-control layout. Validate real L1 pull/pin cancellation and normal later death, pit contact stay/leave at expiry, L2 observation/attack/footstep cancellation with a teammate, and L3 target/search/windup plus protected-only/mixed hiding. Keep PoolSlide's current enable/rig flags untouched; its damage case may use the separately isolated encounter fixture. A single physical client does not certify two-client or physical gamepad behavior.

The favorable crash-refund limitation remains: a server can deliver an effect and lose its durable Consumed response, after which a new owner refunds the unresolved reservation once. The memory backend validates actual callbacks and native scheduling, not real cross-server atomicity or DataStore availability. No new session resumes an old effect.

Finish by stopping Play, verifying fixture-only instances/attributes are absent in Edit, rereading all production Sources and rerunning compile/parity before the feature's mouse publication. The production sources must never contain `NativeFixture`, `ProtectionNativeFixtureRunId`, or a DataStore-memory substitution.
