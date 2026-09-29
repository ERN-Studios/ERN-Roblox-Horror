# Eye-emission filtering review

**Status 2026-09-26: v5, asset 91743869995723, strength 200, is installed on the durable rig.** Native Play inspection showed the dark body and white cores through the actual tinted window during the full tap gesture. Final visual/runtime QA and publication are recorded in the [main handoff](../../../../../docs/LEVEL5_WINDOW_WATCHER_2026-09-25.md). This review preserves the mask's derivation and limits; it does not claim immunity to all filtering artifacts.

The original 2048 mask and a 1024 area downsample map directly only to eye surfaces. A conservative sampling footprint reaches neighboring UV islands. Two triangles (5787/5789) map to the viewer-right brow/hairline near Blender (0.064, −0.086, 2.287), matching the fleck position. Native strength 0 removed it, implicating emission filtering.

Uniform erosion and a global guard (v2/v3) were rejected because they fragmented the small iris UV islands. A targeted three-pixel guard (v4) removed 27 of 9,126 lit texels and retained 99.73% mask energy, but the native strength-200 preview still showed the fleck. Rejected candidate binaries/renders are omitted from this package; hashes remain in `mask-revision-decision.json`.

## Selected v5

`window-watcher-eye-emission-mask-v5.png` applies an eight-pixel guard only around those same brow triangles. It retains 98.34% mask energy and 8,983 of 9,126 lit texels. The eight-pixel support audit reaches neither targeted triangle. The offline render retains substantial round cores with a small lower notch in the viewer-left iris.

- 1024×1024; 25,961 bytes.
- SHA-256: `99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738`.
- Reproduction: `guard_brow_mask_v5.py`.
- Audit: `emission-brow-guard-v5-audit.json`.
- Offline render: `emission-v5-face-strength100.png`.
- Native strength-200 evidence: repository-root `artifacts/level5-window-watcher-20260925/native-white-eyes-v5.png` and `native-white-eyes-v5-tinted-glass.png`.

This does not simulate proprietary Roblox compression or guarantee immunity to every neighboring UV island. Use the main handoff's actual processed-material visual result for acceptance. Original albedo, GLB and blend were not modified.
