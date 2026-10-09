# Slidemouth source pack — 2026-08-28

This supplemental split archive preserves the exact two FBX files supplied for the restored Level 2 Slidemouth encounter:

- `models/level2/slidemouth-bind.fbx` — the 27-bone bind/static rig used by the live Slidemouth template.
- `models/level2/slidemouth-walk.fbx` — the matching one-second, 30 FPS in-place walk cycle used by the live keyframe animation.

The archive is split into 640 KiB parts to stay below the authenticated repository bridge's per-blob transport limit. The reconstructed archive is 12,774,459 bytes with SHA-256:

`742d7324f0604e8bd6ea3500c3c2ba51f5774e2296dcdd88263b13f88a563f44`

Restore and verify from the repository root:

```bash
./tools/restore-slidemouth-assets.sh
```

The four exact PBR maps used by Slidemouth are already preserved byte-for-byte in `assets/source-packs/live-assets-2026-08-26`; this supplemental pack does not duplicate them. Their live Roblox asset IDs remain recorded in `assets/live-asset-manifest.json`.
