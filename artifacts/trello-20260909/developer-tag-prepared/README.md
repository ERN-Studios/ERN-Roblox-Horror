# Developer tag proposal — independently reviewed 9/10

Trello: https://trello.com/c/ZAlinXFV. Baseline/proposed files are isolated here; runtime ZyntraMonetization and DevAccess hashes remain unchanged.

The proposed script reuses the exact existing lobby Supporter style, authorizes Developer through the real server DevAccess module, and displays both badges independently. Developer receives a fixed size-relative screen offset when both badges exist, so separate 180×28 tags have a 2.8 pixel gap rather than distance-dependent stud spacing. Roblox documents SizeOffset in size-relative units: https://create.roblox.com/docs/reference/engine/classes/BillboardGui#SizeOffset.

83 actual-source authority/style/lifecycle checks pass; the entire proposed script compiles. Tests include real DevAccess IDs, simulated profile-load failure, existing/late/replaced Head, respawn, duplicate setup/refresh, round visibility, unrelated GUI preservation and queued work after player departure. Native rendering has not been tested.

The critic's CharacterRemoving → later CharacterAdded gap is now reproduced and fixed. The old proposal failed the new fixture while Player.Character still referred to the retired character. A server-local active-character map is cleared during retirement and required by both deferred Head work and general pass/tag refresh. The exact fixture now passes, including late Head and lobby/pass refresh during the gap, replacement activation and a stale removal event. See `removing-gap-regression.md` for the before/after result. No runtime file has been changed.

Independent reviewer `/root/spawn_diagnosis` inspected the full diff, real setup/pass-refresh context, actual DevAccess whitelist and regression fixtures, then independently reran all **83/83** checks, the complete script compile and baseline SHA checks. Review score: **9/10 for the prepared code/artifact**, with no required correction. Native acceptance remains: Developer-only and dual Developer+Supporter avatar; near/far readable spacing through 65 studs; exact teal/Gotham style; round entry removes both and lobby/respawn restores them. This is not a publication or complete feature score.

## Installed release v1835

The artifact-only statements above describe the earlier preparation checkpoint. Root subsequently installed the exact reviewed proposal. Final independent feature review is **9/10** after the native authority, readability, stacked/solo tags, round visibility and actual respawn evidence. Mouse publication **v1835** was confirmed on 10 September 2026 at **07:18:29.893/.910 Europe/Copenhagen**. See `../developer-native-validation.md` for the precise evidence and limits, and `../developer-trello-readback.json` for independently confirmed Done/complete state.
