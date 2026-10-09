The live replacement uses a small targeted importer; it does not rebuild the map. Studio Play QA passed and the reusable Blender source was integrated on 2026-10-09. See `source-integration-receipt.json` and `qa/studio-qa.json`.

`persist_reflector_source.py` was run offline through the shared Blender slot wrapper. Its reviewed outputs are under `source-draft/`: a reusable asset, receipt, manifest fragment, validation report and a corrected master COPY. The pre-integration master SHA256 was `667313c7a4564b76bc3208bcda2dc0c960d78763fdc4db80f2986b460969cd9d`; the integrated master SHA256 is `166125f6224e005a643b530c43af56c329ff8d62443e723e8c83362b4bb1debe`.

`integrate_reflector_source.py --apply --qa-receipt qa/studio-qa.json` performed the scoped integration with fresh hash checks and backups at `G:/Blender/Level2_Poolrooms_New_20261006/backups/before_A2LionReflection_20261009T124435577027Z`. The asset is registered at `assets/meshy/PROP_bronze_disc_crank_frame_reflection`; the original asset remains available. The instructions below document the reviewed geometry and integration procedure.

The script removes the existing instance's complete world rotation from the prepared vertices and swaps exactly one old collection instance while preserving its local and world transforms. This includes A2's +90 degree parent yaw. The existing -45 degree local instance consequently has +45 degree world yaw; removing only the prepared -45 degree yaw would have doubled an area rotation. The draft preserves both instance matrices exactly, has local foot floor z=0, and its measured disc normal agrees with the prepared manifest within 0.021 degrees. See `source-draft/validation.json`.

The command used was:

```powershell
python 'G:/Blender/Level2_Poolrooms_New_20261006/scripts/blender_slot.py' -b --factory-startup --python-exit-code 1 -P 'G:/Roblox/MongoTV/artifacts/level2-lion-reflection-20261009/persist_reflector_source.py' -- --out 'G:/Roblox/MongoTV/artifacts/level2-lion-reflection-20261009/source-draft'
```

The wrapper uses the installed Blender and the shared one-slot memory gate. The persistence script refuses to overwrite an existing output directory, so a subsequent run needs a fresh directory. Review the output draft and its source receipt. Before integrating, make explicit timestamped copies of the master, `assets/meshy/manifest.json`, and `scripts/areas/A2_solurbadet.py`.

Copy the new `PROP_bronze_disc_crank_frame_reflection` asset folder under `G:/Blender/Level2_Poolrooms_New_20261006/assets/meshy/`. Merge its `manifest_fragment.json` entry into the existing shared manifest, updating the entry's `blend` path to that final asset location. Preserve all other manifest entries and the old reflector asset.

In `scripts/areas/A2_solurbadet.py`, change only the asset name in `build_props`:

```python
return ctx.place("PROP_bronze_disc_crank_frame_reflection", (ISLAND_C.x, ISLAND_C.y, ISLAND_TOP), rot_deg=(0, 0, DISC_ROT),
                 collection=props)
```

Keep `DISC_ROT = -45.0` and the existing floor placement. The reusable asset is stored in the existing instance's local frame, so the instance and A2 parent supply the required rotation exactly once. Only its disc is tilted; frame and feet retain their grounded pose.

The draft master can replace the original only after backup and validation. Future full map builds will then select the reflection asset through the ordinary `l2n.assets` registration. The reflection lighting also requires the scoped runtime skylight patch and the separate `install_reflection.luau` step; this offline source script does not alter live Roblox scripts or lights.
