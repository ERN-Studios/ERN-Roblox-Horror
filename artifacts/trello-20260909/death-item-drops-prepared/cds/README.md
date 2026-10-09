# IpCKlAsz — CD death recovery proposal

Request: “When a player dies while carrying fuses or CDs, drop those items on the ground where they died. Make the dropped items easy for other players to see and pick up.” This directory contains the **CD / Level 3 half only**. Fuses are independently prepared in `../fuses`; no shared source is changed here.

One existing file: `ServerScriptService/Level 3 Systems/Level 3 Objective Controller.ModuleScript.lua`.

- Current raw baseline: `94508b5a6889d729405b8573817326941f6c83465cbb01f407b06c4722382c02`.
- Proposed canonical SHA-256: `f4cedcac2c6ac687c8e84bb9885ce9fab924da65df92ad43e8fc57fd2c0b9453`.
- `prepare.py` requires the exact current baseline, writes only this directory and creates the complete proposed source, before snapshot, diff and manifest. Production and Studio remain unchanged.

## Existing behavior and the precise correction

The current controller already has five authoritative CD records, CARRIED/DROPPED/INSERTED ownership, death connections, per-CD prompts and round cleanup. Those mechanics are reused. CD collection counts are not awarded again on recovery, and the unchanged insertion path consumes the same identities. Disconnect redistribution is preserved; this card changes death recovery, not the separate disconnect policy.

The previous death ray could hit decoration or another character, and returned an unsupported airborne position when it missed. The visual spread was not checked again against the floor. The replacement accepts only the current mall’s actual `Level 3 Room Floor` and `Level 3 Corridor Floor` parts. It deliberately excludes the escaped-player waiting room below the map. Each point needs an upward-facing collidable floor hit and a small world-only overlap check that keeps the flat CD out of walls/table legs. Avatars do not become floor or obstruction candidates.

The actual dying character’s position is tried first. A blocked point gets a fixed local search at 1.5, 3 and 4.5 studs, with eight directions at each radius. The existing 0.1-second session heartbeat records positions and confirmed floor points **only for carriers**; a void death can use its last confirmed floor. If none exists, the first carried CD’s original authored location gets the same nearby-floor checks. This is a small recovery search, not navigation or a new world service. The floor filter is constructed once per round. No unconfirmed coordinate is accepted if the entire playable floor has been removed; that invalid-world case is explicitly tested, not claimed as successful recovery.

Dropped CDs keep their original disc/hub models and stable, noncolliding floor orientation. Wider spacing separates ordinary multiple drops. Every spread point is independently checked, with the confirmed central point as a tight-space fallback. Coincident fallbacks still represent separate, independently collectible CD identities. A steady cyan light and small occluded `CD` label make the pickup visible without flashing or revealing it through walls. The existing **E / touch / gamepad ProximityPrompt, 0.25-second hold and 9-stud distance** remains unchanged.

The lifecycle binding rechecks the session, player, character and Humanoid after `WaitForChild`. It handles already-dead deferred bindings and dead CharacterRemoving. It settles a previous dead character before switching to CharacterAdded, so deferred old callbacks cannot leave that inventory on the new character. Late old death/removal callbacks remain idempotent and cannot drop a later recovered CD. Native session/generation and pickup-distance/living-player gates remain authoritative.

## Focused offline evidence

Run `python artifacts/trello-20260909/death-item-drops-prepared/cds/test_cds.py`.

**387 actual-source checks, three targeted negative controls, and two whole-file compiles pass.** The controlled host executes the actual ground, drop, record/ownership, prompt acceptance, lifecycle and Stop functions. It checks elevated decor exclusion, unsupported/void floor, a wall/table-leg obstacle, nearby source-pivot recovery, all five drops and recovery by another player, repeated callbacks, dead/far/out-of-round pickup refusal, old destroyed prompts, corner fallback recovery, last confirmed floor, generation retirement and actual Stop destruction of drops/prompts/markers. It also covers CharacterAdded before delayed old Died/Removing and three post-WaitForChild retirement cases. The negative controls reintroduce airborne fallback, omit the post-wait fence, or omit settle-before-switch; each fails its intended regression.

Raycast and overlap geometry here are controlled planar/AABB fixtures. Carry decoration refresh, shared-state publication and sounds are bounded stubs; their internals were not reimplemented or claimed as tested. No actual second client, native prompt selection, font/light rendering or Studio scheduling is certified by this offline result. The actual source transform and unchanged runtime hash are also checked. Independent critique is requested separately.

Independent critique is **9/10** for proposal `f4cedcac…b9453`; see `independent-review.md`. The critic independently reran all 387 checks, three negative controls and both compiles. The combined fuse/CD feature and native behavior are not yet approved or published.

`validate-world-callsite-note.md` documents the current suite callsites: no production caller invokes `TestSuite.ValidateWorld`. The normal adapter uses its own manifest validator. A manual structural validation after dynamic drops can encounter the suite's existing text restriction, so run that structural check before drops and use the separate runtime/drop observations afterwards. No test rule is weakened by this proposal.

## Later native acceptance for root

Use the shared `../native-readonly.server.luau` prepared by root for observations; do not introduce a duplicate helper. It does not establish gameplay success by itself. No native action is authorized or executed by this artifact task while the owner requests code-only work.

1. After root’s scoped installation and compile/audit, enter a **normal Level 3 round** and collect real CDs through their actual prompts. Record each identity, carried mask/count and collected/inserted totals.
2. Test an ordinary floor death with one CD, then five CDs near an actual wall/corner or table leg. Use the real dying character’s position; record actual floor support, dropped model positions and enabled prompts. Inspect the steady light/label in the normal dark level and from another player’s viewpoint.
3. A second real living player collects **all** drops through normal prompts, including any coincident safe fallbacks near the corner. Confirm each CD transfers once, every drop model/marker disappears, carried total matches and the original collected/inserted progress is not awarded again. A one-client diagnostic must be labelled accordingly and cannot prove other-player pickup.
4. Verify death followed by respawn/re-entry leaves the new character empty until a normal pickup; late callbacks cause neither new models nor lost freshly recovered inventory. Confirm normal stop/round replacement removes the runtime folder and leaves no old prompts/markers.

Keep existing CD objective/insertion behavior intact. Root owns native control, source installation, full-source audit, the final independent feature score and a separate mouse publish.
