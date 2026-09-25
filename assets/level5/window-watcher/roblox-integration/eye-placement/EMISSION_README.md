# White-eye emission — selected v5 checkpoint

The selected mask is `window-watcher-eye-emission-mask-v5.png`, uploaded as **91743869995723**. It is 1024×1024, 25,961 bytes, SHA-256 `99315f05889bbc4c9f1122f502913bef7bf3fd5d7742b2a5a30ded79fee45738`.

Call `Apply(rig, 91743869995723, 200)` from `../tools/install_watcher_eyes.luau`. Default strength is 200; the accepted range is 5–200. The dark original iris albedo left strengths 15–30 gray in native tests. Strength 200 produces the requested white cores.

The installer requires the frozen GLB hash and ActorHeightStuds=8, preserves ColorMap `rbxassetid://91091934459636`, and creates an owned SurfaceAppearance. The emission follows the skinned iris directly. It creates no GUI, physical Light, additional geometry or update loop. Conflicting foreign appearances/eye markers cause an explicit error; only owned obsolete Billboard attachment trees are removed.

Temporary native Studio previews established white eyes and visibility through matching tinted Glass. The original BillboardGui design was rejected because Glass occluded it. **Final filtering sign-off is pending:** a tiny brow fleck needs reinspection after Roblox material processing and on the durable imported rig. No runtime rig or encounter module has been installed or published.

## Reproducible anatomy and mask

- Iris core diameter: 0.067 studs on the eight-stud model, soft edge to 0.075 studs.
- `bake_eye_emission.py` produces the preserved original 2048×2048 mask from actual geometry; original GLB, albedo and blend are unchanged.
- Its direct UV mapping audit checks 34,280 non-black texels, mapping only to Head-weighted eye surfaces within 0.011146 metres of the centers. This is a texel-center audit, not immunity to filtered sampling.
- `guard_brow_mask_v5.py` derives the selected mask using an eight-pixel guard around two neighboring brow UV triangles. It retains 98.34% mask energy.
- See `MASK_FILTER_REVIEW.md`, `emission-brow-guard-v5-audit.json` and the native screenshots in `artifacts/level5-window-watcher-20260925/` at repository root.

The retained attachment-coordinate JSON and marker authoring scripts are anatomical evidence only. Do not install the superseded GUI approach.
