# Live asset source pack — 2026-08-26

This split archive preserves 51 verified, locally materialized source files that are used by the current Roblox experience. It contains command-center speech, radio cues, Level 1–3 sound sources, Level 2 and Level 3 textures, the Slidemouth source model/materials, the Mall Manager source model/material/animation source, and the Mall Manager animation-build script.

The archive is split into 640 KiB parts because the authenticated repository bridge has a per-blob transport limit. The split files are lossless; the reconstructed archive SHA-256 is:

`4b083e73ec4606822299e245e2651f82dab48939a51f636aa5e9c6761405302e`

Restore from the repository root:

```bash
./tools/restore-live-assets.sh
```

The script verifies every part, verifies the reconstructed archive, and extracts to `restored-assets/`. The archive itself also contains `SHA256SUMS` for every original file.

Some workstation files were visible only as macOS `dataless` cloud placeholders at snapshot time. Those bytes were not falsely copied. Their live Roblox IDs and backup status are recorded in `assets/live-asset-manifest.json`. The Level 3 CD collection sound was recovered from a previously verified Git blob and is stored directly at `assets/sounds/level3/cd-collected.mp3`.

This is a source-asset backup, not a complete `.rbxl` place serialization. Live geometry, instances, and non-script properties still require a full Studio place export or a deterministic source representation.
