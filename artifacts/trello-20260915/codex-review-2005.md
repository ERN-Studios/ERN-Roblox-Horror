# Codex coordination and review — 20:05 UTC

## #36: completeness blocker for migration

The per-stream max ceiling is a lower bound, not exact reconciliation. Counterexample: stored utility=100 from newer purchases outside the CSV plus export=50 from old uncounted purchases; correct150, max100. Another: export100 with old uncounted30 + counted70, and stored100 from counted70 + new30; true130, max100. Thus preserving the stored scalar does not preserve both sets of history. Do not silently label this complete or run this irreversible marked-done migration as the final all-purchases import. No numeric proof can infer the unknown overlap from two aggregate numbers alone.

Please have A36 distinguish an exact path from lower-bound fallback, gather actual read-only live profile/receipt evidence if available, check CSV base64 GUID conversion against raw PurchaseId variants (normal and .NET mixed-endian) without logging buyer data publicly, and inspect historical version adoption/counting boundaries. A read-only audit must precede mutation. If exact historical coverage remains unrecoverable, surface the specific ambiguity with per-buyer private audit and a reviewable choice instead of claiming exact completion. Do not enable Studio API/game security settings just to get data. Existing user instruction to update all purchases is authoritative, and new/post-export spend must survive.

## Assets / Studio window

All 12 requested imagegen PNGs now exist under assets/shop (masters in source/, README and generation-registry.json). Codex requests the next bounded Studio window for image upload only, or coordinate a safe upload concurrently if the MCP upload does not interfere with the agent's test. No source/play-state changes by Codex until explicit handoff. Notify via claude-status.md with Studio free/assigned and mode; normal next check20:15 UTC.

## #99 Blender animation

Blender 5.2 MCP bridge 127.0.0.1:9876 is confirmed working through tools/blender_mcp_client.py. Initial scene contains only default Camera/Cube/Light and has no filepath; preserve it. Animation-handoff.md received, with R15 AnimationConstraints, root at floor+2.20, collider underside2.76 and both lane limits. Please have A80 export exact template/live character part sizes/CFrames and each AnimationConstraint's Attachment0/1 local CFrames, Part0/Part1 equivalents and names into artifacts/trello-20260915/hiding-rig.json. Include root-relative transforms and body bounding geometry (accessories if possible). This lets Codex author and bake against the real rig rather than guessed R15 proportions. A80/lead should own integration of the returned clip id/baked data and one-pose-writer fallback, preserving ordinary crouch and observer behavior.
