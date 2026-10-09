# Next native pass: actual death and another player's pickup

Instructions only; no UI, Studio, production or Trello operation performed. This is one feature with two source files, to install/publish together **after the separate full-circle checkpoint**. Existing479 actual-source checks/five negatives and9/10 prepared review are retained; no new host or broad retest is needed.

## Exact installation inputs

All paths below are relative to `G:/Roblox/MongoTV`. The initial read-only disk check matched both original baselines. During this preparation root began the installation; the final disk read now matches both exact reviewed proposal hashes. That is disk provenance, not an independent Studio audit or a write by this subtask. Root owns the actual stopped-Edit compare/readback.

| Runtime path | Original input raw SHA256 | Reviewed proposal/current final disk SHA256 |
|---|---|---|
| `ServerScriptService/Level 1 Systems/PuzzleManager.Script.lua` | `4c0b34b99dfb6c09b439d06ab4cbab65fa0049f25ce09392f1032d7d258465eb` | `204f3edd93c7970882a2379a12c141b55acc3c941f137ee48e5955fc3e2e090c` |
| `ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua` | `94508b5a6889d729405b8573817326941f6c83465cbb01f407b06c4722382c02` | `f4cedcac2c6ac687c8e84bb9885ce9fab924da65df92ad43e8fc57fd2c0b9453` |

The corresponding complete proposals are under `death-item-drops-prepared/fuses/proposed/` and `cds/proposed/` with these same runtime paths. Fuse baseline canonical-LF SHA is `a1106750a601641302d2be41f5940b09b97c13a06d33ba8a57e8b2a7c3eb8111`; CD baseline is already LF. Use the existing backup/UpdateSourceAsync/readback/compile process, preserving GameManager and all earlier releases.

## Smallest useful real session

Use **two real Studio clients A and B**, both in the same normal queue/round. Keep B living, InRound and unescaped while A dies. Do not fabricate a second Player or set InRound/held counts. A solo death opens the existing15-second Party Down grace, then normal loss cleanup; solo can show a temporary drop but cannot prove another-player recovery. Do not disconnect A: CD disconnect redistribution is deliberately different from death.

Three short normal rounds cover the new native risks without purchases or inventory grants:

1. **Level1 floor/wall: two real fuses.** A uses two actual `FuseRelay` extraction prompts:1.8s hold, then the existing.55s release. A's normal `PuzzleGui` descendant `FuseCarryStatus` must say2. Die on actual carpet next to a wall/fixture with a walkable approach; use normal damage, or the disclosed controlled Health=0 command below. Save the exact pre-death root position. One `Workspace.PuzzleItems.DroppedFuses` must have `FuseCount=2`, A's carry becomes0, and no second model appears after the normal corpse removal. Verify the gold label/light from B's real viewpoint, walk up and hold the real pickup prompt for.25s. B's carry must increase by exactly2 and the model disappear. Another E hold must not add inventory. Insert one recovered fuse through one actual box prompt: B falls to1 and exactly one box advances. An objective target at another surviving relay is legitimate; a dropped fuse need not be selected if a prior relay remains. It must not point at a destroyed core or become absent merely because the carrier died.

2. **Fresh Level1 pit: one real fuse.** Return normally after the prior round, queue both again, collect one real fuse and have A fall through an actual `Workspace.PitZones.Zone` hole to the existing lethal bottom while B waits safely. Avoid Entity Shield/noclip/invulnerability during the fall. Keep the actual pit/ground coordinates. The recovered stack must be on accessible horizontal carpet/gangway near that death XZ, not at the approximately−50-stud kill floor or suspended in a hole. B must actually reach and collect it. This tests native raycasts plus accessibility; do not move the dropped model onto a floor for the test. A normal carpet part under `Workspace.Maze` and pit gangways share anchored Fabric/height1/centerY−.5. The invisible Zone center alone is not necessarily an open hole—inspect the actual floor before moving into it.

3. **Fresh Level3: same real CD recovered by B.** Queue both directly into a normal Level3 round; this feature does not need the L2→L3 slide. A collects one real CD; leave the disc player alone so no inserted progress unlocks the exit. Record its actual index, A's held count1/corresponding mask, original collected1 and inserted0. Let the actual carrier heartbeat run at least.2s on a confirmed room/corridor floor, then die while B lives. There must be the same dropped index and A held0/mask0. Inspect its cyan label in the normal dark scene; B picks it up through the actual.25s prompt. B becomes1/the same mask, dropped0, original collected remains1 and inserted remains0. An authored source model/tag persists after collection; its state/owner and the dropped model, rather than existence of the original jewel case, establish ownership. A small multi-CD/corner extension is appropriate if actual spacing/selection raises a concern; the historical five-CD matrix is not a mandatory new test sweep. If a tight-space case is observed, every distinct dropped identity must remain reachable/selectable; do not silently skip a coincident prompt.

End the last round through the existing normal result/return, or a clearly disclosed controlled wipe followed by the normal15-second loss/cleanup. Save before Stop: new living lobby characters, old `PuzzleItems`/L3 world removed, no old drop models/prompts, and cleared CD held attributes. A fresh normal queue must not restore prior inventory. A same-round re-entry case is optional only when an already available entitlement can be used without a purchase or granting credits; the pending free-DEV-respawn feature is not installed authority. A normal next-round reset is not relabeled as same-round re-entry. The already-reviewed deferred-callback, all-floor-rejected and subsecond extraction races remain actual-source evidence unless independently observed; do not manufacture native coverage for them.

If staying in the already running two-client campaign is faster than another lobby queue, after the final fuse observation root can set the actual L1 `PuzzleWon=true`, allow the normal15-second default Continue, wait for both actual L2 characters/controls, then do the same once in L2 to reach the normal L3 service elevator. The current GM's post-win roster keeps actual connected participants even if one is dead; verify both next-level characters instead of assuming this happened. This is controlled objective completion, not puzzle completion or the L2 exit-sensor route. It does not set Escaped, alter deadlines, grant inventory or invoke a fresh module. In the actual Play server, use the current observed level explicitly:

```lua
assert(game:GetService("RunService"):IsStudio() and game:GetService("RunService"):IsRunning())
assert(workspace:GetAttribute("SelectedLevel")==1 and workspace:GetAttribute("RoundActive")==true)
workspace:SetAttribute("PuzzleWon",true) -- actual normal result pipeline; later use2 only after real L2 ready
```

Do not run the second command immediately: the normal15-second result window and actual world/character readiness must occur first. This route bypasses no pickup or Died callback under examination. Use normal final L3 return for the final lifecycle observation.

## Existing observations and tiny commands

The actual local-server/child-client windows are Command Bar contexts, not the authoring window's MCP state. Run **`native-commandbar.server.luau`** once in that actual server. Its own `_G.TrelloDeathDrops` exposes:

```lua
return _G.TrelloDeathDrops.Targets() -- actual enabled prompt paths/positions
return _G.TrelloDeathDrops.Approach(-1, 1) -- observed Key from Targets(), not list index or duplicated path
_G.TrelloDeathDrops.WatchDeath(-1) -- actual current Humanoid.Died, useful before the real pit fall
return _G.TrelloDeathDrops.Kill(-1) -- disclosed Health=0, requires a real living teammate
return _G.TrelloDeathDrops.Read() -- actual approaches/deaths
_G.TrelloDeathDrops.Stop() -- disconnect only this fixture; also expires after600s
```

Replace−1 with A's actual observed UserId; use B's ID for B's approach. Targets assigns observer-private Keys to actual prompt references because multiple FuseRelay models have identical full paths. Keys survive another Targets call within this helper and are invalid after replacement; an old destroyed/disabled prompt is rejected. Approach returns the exact current Prompt/PromptPosition for the client. No gameplay attribute is added. Approach searches actual authored floors around the chosen prompt and checks the character's full current bounding box, other avatars, line of sight and prompt distance. It fails without moving if no clear candidate exists. It never moves a pickup, changes membership, or grants inventory. A reported candidate is controlled staging; root still observes actual client entry readiness and the prompt's normal UI. The helper preserves actual generation state and requires an active living participant, but does not claim a production private-session query.

In the matching child client, substitute the real UserId/full prompt path **and exact PromptPosition** in **`native-prompt-input.client.luau`**. It refuses anything except one enabled path+position match, so same-name relays cannot silently substitute for each other. It calls public `UserInputService:CreateVirtualInput()` / `SendKey(true, Enum.KeyCode.E, false)`, holds with bounded Heartbeat/context checks and attempts an owned E-release on completion/error/cancellation. Require `Released=true`; any ReleaseError must be resolved with its own `_G.TrelloDeathDropInput.Stop()` before another input. Actual Triggered ends the hold successfully even if the game immediately destroys the prompt. The helper waits.7s for the fuse's.55s release, then records actual Triggered, carry/CD readbacks and character/round/health. `[DEATH_DROP_INPUT]` is one concise JSON line, also retained as `_G.TrelloDeathDropLastInput`. A successful SendKey call alone is not pickup; require actual Triggered plus the server/model/count change. If Command Bar focus consumes the input, focus the actual viewport and repeat that input setup; do not fire the prompt or pretend the failed attempt succeeded. Multiple target-specific invocations may be pasted sequentially after root has staged the actual character for each; there is no scripted inventory loop or fake interaction.

Run the already-reviewed **`artifacts/trello-20260909/death-item-drops-prepared/native-readonly.server.luau`** in the actual running server before death, after death, after B's pickup and after cleanup. Save its JSON separately at each step. It enumerates actual drop identities/counts, positions, prompts, labels, players and shared CD progress, but cannot read private fuse inventory or prove rendering/collision. No normal-module require is needed.

Read the actual carry HUD on **each matching client**, before collection and after death/pickup; this is the normal UI's server-driven count, not a fabricated hand-visual count:

```lua
local p = game:GetService("Players").LocalPlayer
local g = p and p:FindFirstChildOfClass("PlayerGui")
local panel = g and g:FindFirstChild("PuzzleGui")
local label = panel and panel:FindFirstChild("FuseCarryStatus", true)
return {UserId = p and p.UserId, Text = label and label.Text,
    Visible = label and label.Visible, GuiEnabled = panel and panel.Enabled}
```

For navigation, discover **actual existing** item targets in the current world; do not assume generated suffixes or positions. Read-only server command:

```lua
local out = {}
for _, m in ipairs(workspace:GetDescendants()) do
    if m:IsA("Model") and ((m.Name == "FuseRelay" and m:GetAttribute("ContainsFuse") == true)
        or m:GetAttribute("Level3_CDSource") == true) then
        local p = m:FindFirstChildWhichIsA("ProximityPrompt", true)
        if p and p.Enabled then
            local h = p.Parent
            local v = h:IsA("Attachment") and h.WorldPosition or h:IsA("BasePart") and h.Position
            table.insert(out, {Path=m:GetFullName(), CDIndex=m:GetAttribute("Level3_CDIndex"),
                Prompt=p:GetFullName(), Position=v and {v.X,v.Y,v.Z}, Hold=p.HoldDuration})
        end
    end
end
return out
```

If faster controlled death is necessary, root can run the following in the **actual Play server** after selecting A from the observed roster and recording the real carry HUD. This is a disclosed mutation of the actual Humanoid, not a death-playthrough or a debug-drop substitute. Replace the two IDs with those actually read; local Studio−1/−2 are examples only.

```lua
local P, R = game:GetService("Players"), game:GetService("RunService")
assert(R:IsStudio() and R:IsRunning() and R:IsServer())
assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407)
local A, B = assert(P:GetPlayerByUserId(-1)), assert(P:GetPlayerByUserId(-2))
assert(A ~= B and workspace:GetAttribute("RoundActive") == true)
local level = workspace:GetAttribute("SelectedLevel"); assert(level == 1 or level == 3)
local c, other = assert(A.Character), assert(B.Character)
local h, bh = assert(c:FindFirstChildOfClass("Humanoid")), assert(other:FindFirstChildOfClass("Humanoid"))
local r = assert(c:FindFirstChild("HumanoidRootPart"))
assert(h.Health > 0 and bh.Health > 0 and A:GetAttribute("InRound") == true
    and B:GetAttribute("InRound") == true and A:GetAttribute("Escaped") ~= true and B:GetAttribute("Escaped") ~= true)
local v = r.Position
local before = {At=workspace:GetServerTimeNow(), UserId=A.UserId, Position={v.X,v.Y,v.Z}, Health=h.Health}
h.Health = 0
return before
```

For the pit case, use the actual fall; do not set Health=0 while still on the walkway and call it pit recovery. A before/after snapshot plus the real fall and recovered-ground image is sufficient; there is no need for a continuous300Hz logger.

## API and evidence boundaries

- PuzzleManager is a **Script with private session state**. There is no legitimate DebugGiveFuse/DebugCollectFuse API. Use real relay/drop/box prompts; do not mutate `session.carried`, fake carry remotes or call connection internals.
- Existing CD `DebugCollectCD(player,index)` delegates to the actual validated collectRecord (alive/member/distance/LOS/current generation); `DebugInsertHeldCDs(player)` delegates to insertion. These require a **normal server Script's shared production module singleton**, not a fresh MCP `require` cache. They may support a explicitly labeled diagnostic if needed but do not prove physical prompt input. `DebugDropHeldCDs` bypasses the death signal and must not replace this feature's death acceptance. No extra module bridge is needed for the proposed normal-prompt flow.
- Snapshot rays/part positions alone cannot certify a safe footprint. Use the rendered floor/contact plus B's actual approach and successful prompt. A missing valid floor is a fail-closed preservation case already tested offline, not a request to remove floors in Studio.
- The existing Level3 manual `TestSuite.ValidateWorld` has a blanket text restriction that can reject legitimate runtime drop labels after dynamic pickups. `cds/validate-world-callsite-note.md` shows production uses the adapter validator, not that manual suite. Do not weaken the suite or call its dynamic-label refusal an unexpected gameplay failure; structural validation precedes drops.
- No account purchase, forced token/credit/charge, new Player, entitlement change or DataStore write is part of setup. If root uses AI pause to keep B safe, record its Play-only use and clear it for normal cleanup; it is not natural combat evidence. Do not claim a native race/prompt-denial test merely because a guarded offline host passed.

Prepared-code score is9/10; final native assessment and one separate mouse publication of both halves remain root-owned.
