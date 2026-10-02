# Spawn migration audit and file-only candidates

The authoritative Studio was read in Edit mode on 2026-10-02. Place 131311258779917, universe 10559217407, Studio instance 0552e451-d540-464e-ad9f-478d00392f88. The checkout was at c5ddf1e; no Git remote was configured. No Studio instances, properties, Source, settings, or Git index were changed by this audit.

## Canonical spawn contract

All audited lobby placement paths resolve the same `Workspace.ServerLobby.LobbySpawn`:

- GameManager initial character placement, non-round death respawn, local round teardown, and mid-round local return.
- Level 4 legacy and V4 developer preview returns.
- Level 5 developer preview return and unauthorized-preview recovery.
- Level 6 developer preview return and runtime death/leave return.
- RoundUI lobby welcome proximity.

Preserving the name, parent, instance reference and pad size avoids replacing these existing routing paths. The intended target is position (220,30.4,-860), facing the new lobby center (220,30.4,-760). GameManager's existing lobby scatter remains within ±2 studs in X/Z and uses a yaw of π.

Fresh Source/editor equality and SHA-256 hashes are recorded in `source-hashes.json`. Full exact baselines for the four initial candidates are in `candidate-baseline-sources.json` and the file-only candidate directory.

## Startup order and safe failure

The original TunnelLobbyBuilder creates the original spawn, starts LobbyShopDisplay asynchronously, and immediately returns. The shop Model is parented before its contents are finished; the existing `ShopItemCount > 0` marker is assigned after every product and stand has been created.

The GameManager wrapper candidate preserves the original builder and geometry. For normal public lobbies it waits at most 20 seconds for the shop completion marker, builds the revised lobby synchronously, verifies its ownership/readiness/center and nine solid scatter-floor rays, then moves the same canonical spawn. This runs before GameManager connects/setup-loads lobby characters. Reserved round servers bypass the new build.

On any migration failure, the old spawn CFrame remains available and a clear readiness/error diagnostic is published. This fallback keeps arrivals safe; a failure is a material blocker for claiming the migration complete or publishing it.

Bootstrap becomes a bounded 60-second readiness monitor. It never calls Build, so it cannot race GameManager's authoritative build. Its polling retries only the readiness observation, not a parallel construction transaction.

At audit time the revised lobby Model was absent from Edit Workspace. No actual new-floor check or spawn gameplay pass is claimed from this source audit. Root will build/verify the native Edit lobby and run actual Play tests.

## Level 6 floor acknowledgement

Level6PreviewTransport raycasts only within the exact model name sent by Level6PreviewAccess. The new floor belongs to LobbyReimaginedPreview, while the canonical SpawnLocation remains under ServerLobby. Keeping the old hardcoded return model would therefore make the return acknowledgement time out.

The paired candidates choose the known new floor model only when the canonical server pad carries that exact marker; otherwise the old ServerLobby fallback remains valid. The client whitelist adds only the exact LobbyReimaginedPreview name. Server authorization, nonce ownership, proximity, current character, and preview-runtime guards remain intact.

Level 4 legacy/V4 and Level 5 previews only call RequestStreamAroundAsync on the canonical pad position on return. They do not use a client floor/model-name acknowledgement. Level 6 runtime death-return similarly requests streaming without that strict model filter. Fresh contexts are in `preview-return-streaming-audit.json`.

## Necessary client dependency

Friend Boost Client measures only ServerLobby's bounding box. Moving just its pad does not cover all of the new lobby and can leave stale cached bounds. Its additional candidate follows LobbyReimaginedPreview only if the canonical pad selects it and the revised Model is owned and ready. Otherwise the old selector remains valid. Existing round/loading/modal guards, invite behavior and server-owned bonus authority are unchanged.

The fresh Friend Boost baseline is f23f18b67d9858ee72263f622098a7e5e8bb65b0b64942306f591c775ef02262, 8742 bytes. Its candidate is cc1de5da96026536aa278e46aa0506bd0c0777816fcf93cf33d6bbf79bda0984, 9252 bytes; compile-only verification passed.

A bounded fresh-source scan of ServerLobby references combined with GetBoundingBox/GetPivot/camera/minimap/visibility, plus -760/-860 and spawn literals, found no additional positional client dependencies requiring this task's changes. RoundUI already follows the canonical pad. Shop Display Client's ServerLobby selector is for the original shop's bobbing; the revised clone intentionally uses fixed cards.

## Verification

Fourteen pure mocked startup cases passed in a Studio command sandbox at 15:24:43Z. All models/workspace/required builders were fake tables; no DataModel write occurred. These cases cover ready and delayed-shop startup, reserved-server bypass, bounded missing-shop failure, missing/throwing builder, unowned/unready/wrong-center models, missing/non-solid/steep/wrong-height floor, and a changed canonical pad.

These fixtures verify control flow and failure safety; they do not establish actual streaming, collision or gameplay success.

Actual Play checks still required for root:

1. Fresh developer and ordinary-player lobby arrival at the new pad, facing +Z, alive on the road; normal players must not need a developer to join first.
2. Death/reset respawn returns to the same new lobby and restores movement.
3. Level 6 preview enter and actual return prompt acknowledge the new floor and return alive to the new lobby.
4. Other preview returns continue to resolve the same pad; campaign return/cleanup restores it consistently.
5. Friend Boost chip remains visible across the new tunnel and bays, and hides during rounds and screen-owning modals.
6. Confirm the revised lobby remains beside the original, and the original geometry/queues are preserved except authorized spawn properties.
