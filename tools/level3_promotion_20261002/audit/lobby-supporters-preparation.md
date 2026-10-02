# Original supporter board: read-only preparation

Evidence is the last verified Studio export at `/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-lobby-access-spawn/after/scripts.json`, captured 2026-10-02 at 16:11:03Z. It is historical evidence, not the baseline for a Studio write. No Studio source, repository mirror, Git index, or runtime instance was changed in this audit.

The checkout has local modifications and many untracked files. `HEAD` is `92c3b58` on `main`; no Git remote is configured, so current remote history could not be queried.

## Original data and rendering

- `ServerScriptService.TunnelLobbyBuilder` (ModuleScript, source/editor match; SHA-256 `325c1d220069976ff2a8205ef062837ffd74c9c3808b3a8d85fd270ff483417a`) has one support board builder at lines 416–657. `addDonationLeaderboard` creates `ZyntraDonationLeaderboardBoard`; the title is `TOP SUPPORTERS`. It is called once by the original concourse builder (line 2553).
- This board combines recorded donations, utility Developer Products, storefront passes, and private-server purchases. Exhaustive search of the export's 228 script sources found no separate buyer leaderboard builder or provider. Do not manufacture a second ranking under an invented meaning of “buyer.” Verify the requested terminology against fresh live Studio instances.
- `ServerScriptService.ZyntraMonetization` (Script, source/editor match; SHA-256 `f1e8b13d210ddd4e098bc2bed42e36fad4b5d043295f198663f5e89beaca059e`) owns the single OrderedDataStore and publishes `ReplicatedStorage.ZyntraDonationLeaderboard` (Folder). Its `Status` and `Row01`–`Row10` are StringValues. Each row also carries the `Rank`, `Name`, and `Robux` attributes.
- `ReplicatedStorage.ZyntraConfig` (ModuleScript; SHA-256 `c9824bc6d3959f9f500eb09f0217b7f3787acc0c089136b3c3154077e8df374f`) names `ZyntraDonationLeaderboard_v2`, requests ten rows, and sets the normal refresh interval to 90 seconds. The provider also refreshes after successful support-cache writes and sales imports. Studio uses current session totals instead of live OrderedDataStore reads.
- The original renderer subscribes to `Status.Value`, every row's `Value`, and all three column attributes. It formats thousands separators, supports legacy row strings, clears empty ranks/amounts, and preserves the ten-row aligned layout. It disconnects its handlers when the board's direct Parent becomes nil. Cloning only the model would copy labels, not those closure-held signal connections.

## Scoped integration recommendation

Relocate the actual fresh runtime-created board directly from the original concourse into the revised R4 model. Direct reparenting with a non-nil new parent preserves the original renderer's board/label references and existing signal connections. Translate the board pivot by `revisedCenter - originalCenter`; preserve the original parent and pivot and restore both before destroying a failed revised build. This needs no new datastore, receipt logic, monetization polling, or duplicated renderer.

Apply this in the current live `ServerScriptService.LobbyReimaginedPreview.Builder` against a fresh Source/editor baseline. Its historical source/editor hash is `6154d95902fbe2d89976e6428fc38a69f25e91e78f5ad02afac50ef19a39fad7`. Historical `GameManager.buildLobby` constructs the original lobby first, waits up to 20 seconds for its existing shop completion marker, then synchronously calls the R4 builder before loading any lobby character. The board is already constructed synchronously by that point. Historical GameManager source/editor hash is `cd045eee01354ea97fb49b35a78a31a968aab47a8cdd34cb34a3d16318416a11`.

The historical original center is `(0,30,-760)` and revised center is `(220,30,-760)`. Original board panel relative center is `(-30,7.15,-35)`, size `(.62,12.6,18)`, SurfaceGui Right face, canvas `560×392`. Translation puts it at `(190,37.15,-795)`. Its existing blocking footprint relative revised center is X `[-33.05,-29.69]`, Z `[-44,-26]`, between the Level 1 and Level 3 doorway rows. The R4 asset manifest shows a lower wall at X `[-34.85,-33.55]` over Z `[-60,-20]`. These static dimensions make that original position plausible; they do not establish gameplay clearance or visual fit.

An alternative, if retaining simultaneous original and R4 displays is explicitly desired, is to expose and reuse the original builder renderer so both displays subscribe to the same existing replicated values. A visual clone alone is insufficient.

## Required fresh verification

1. Inspect exact live board instance(s), original builder, R4 Builder, Monetization, and Config; resolve any Source/editor conflict before CAS edits. Reconcile concurrent changes with live Studio.
2. In a running fresh public lobby, confirm one functioning board in R4, no unintentional duplicate visible board, unchanged title/row layout, readable face, safe walk-up distance, and no obstruction of queues or floor collision.
3. Prove a real running board responds to Value and all three attribute changes, status changes, and empty rows. Restore provider-owned probe values after bounded testing, and verify actual provider publication afterward. Do not claim a live purchase or cross-server datastore check from a Studio session test.
4. Verify failure rollback leaves the original board safely parented and its renderer functioning. Verify rebuild/re-entry/reset retains only the intended board and disconnects handlers on destruction.
5. Capture verified native backup and exact source/property records, inspect staged task-only diff, commit, and publish the existing authorized experience only after material checks pass.

The unidentified sign is intentionally outside this recommendation until its exact target is clarified.
