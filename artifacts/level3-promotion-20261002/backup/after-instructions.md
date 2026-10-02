After preparation is complete. Do not start capture until root confirms that Play stopped and the identified main Studio place is in Edit.

1. Backup owner verifies and stops only the owned before receiver PID 28326, then starts:

   `python3 tools/level3_promotion_20261002/backup/receiver.py --phase after --dest '/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion'`

   Check `/health`: task `level3-promotion-20261002`, phase `after`, destination ending `/after`, and `frozenInMemory=true`. Loader SHA256 is `ecdf7b764b97d454da49432f99ba9c6d8587aaebc0d5120b6ce95bb17418eb5c`; schema SHA256 is `f9b340d8ceb219d64226320a1a7b9af2f00e2fb2bd81b3355c100423bf82ac08`.

2. Root runs the existing frozen `/capture` loader only in main Studio `c1e8b040-e549-408a-8a5b-7fe6905c2d55`, checking place `131311258779917`, universe `10559217407`, creator `1039373905`, and `RunService:IsRunning()==false`. Keep the existing HttpEnabled setting. The loader captures current Source/editor pairs and native roots; it does not install scripts or assets.

3. Wait for session status `shared.__level3PromotionBackupStatus` to say complete and for receiver completion with a fresh after capture id. Preserve the before directory. Save Studio's current native `Download a Copy` to `/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/after/after.rbxl`, with no intervening Source/game edits. Report the actual file path and byte count to backup owner.

4. Run Source-scope integrity validation (compact receipts only):

   `python3 tools/level3_promotion_20261002/backup/verify_after_source_scope.py --dest '/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion' --artifacts artifacts/level3-promotion-20261002/backup --install-manifest tools/level3_promotion_20261002/install-snapshot/manifest.json`

   Expected: 231 exact Source/editor pairs, all 14 installed task scopes match the frozen install hashes, exactly three new Sources plus eleven scoped edits, and all 22 original Level 6 Sources unchanged. Unexpected concurrent changes are reported, never restored.

5. Verify the actual saved native place without duplicating the native forest on disk:

   `/tmp/level3-promotion-backup-lune-20261002/lune run tools/level3_promotion_20261002/backup/verify_native_source_structure.luau '/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/after' '/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion/after/after.rbxl' artifacts/level3-promotion-20261002/backup/after/native-source-structure-parity.json`

   This proves all captured native root class/name/descendant counts and every Source/editor baseline in the saved place. Scoped canonical hashes are separate from whole-forest property equality, which is not claimed because native Save and SerializeInstances differ in child ordering, tiny transform encoding and saved Camera state. No service-property reconstruction occurs.

6. Compare original Level 6 geometry/code roots between fresh captures:

   `/tmp/level3-promotion-backup-lune-20261002/lune run tools/level3_promotion_20261002/backup/compare_original6_native_roots.luau '/Users/zeanjuul4/Documents/Roblox Studio Backups/20261002-level3-promotion' artifacts/level3-promotion-20261002/backup/after/original6-native-root-parity.json`

   Five roots are checked: `ServerScriptService.Level 6 Systems`, `ServerScriptService.Level6PreviewAccess`, and the three `ServerStorage.Level6BlenderSource`, `Level6BlenderSourceRevision20261001`, `Level6TextureImportReferences` roots. Full Source preservation is checked separately for all 22 originals.

7. Export the 14 verified task Sources from the fresh after capture to the exact repository mirror paths in `after-preparation.json`. Do not copy candidate files as Studio evidence, bulk-export over unrelated mirrors, or touch unrelated Git conflicts. The backup owner writes receipts only; root controls these scoped mirror writes, staged-diff inspection, commit and publication.

If native UI saving remains blocked, retain the complete raw after forest, service metadata and all Source/editor pairs and report the actual native-file limitation. Source integrity/export can complete independently; a source-only mirror is not a complete native place or a successful publish.
