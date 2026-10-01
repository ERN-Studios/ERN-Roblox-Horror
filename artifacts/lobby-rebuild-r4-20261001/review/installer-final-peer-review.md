# Exact R4 installer peer review

Reviewed prepared installer SHA256 `4b27b3958bd76574e9721791af45ea76b4d4647ab2bdbf5ad7b48b260fefb6a2` plus `tools/lobby_reimagined/install_r4.py` and `serve_r4.py`.

PASS for exact guarded installer source design; intentionally blocked and not executed. No Studio calls or installer execution were performed.

The persistent scope is restricted to one additive owned R4 payload, seven existing Source/editor CAS updates, and the installed hash attributes on the three owned preview modules. It performs no scene replacement, original-object deletion, repository bulk push, settings/access change or publication. Exactly three static PBR appearance templates are authored off-tree in Edit; runtime protected property writes are excluded.

Fresh recovery proof, place/universe/group/Edit guards, captured full native forest comparison, all captured Source/editor parity, exact scoped baseline hashes, inside-callback CAS, download hashes and post-write parity are present. The current readyForInstaller=false assertion prevents staging or persistent writes while the nine PBR IDs are absent.

The two review findings were fixed: attempted writes are recorded before UpdateSourceAsync and failure snapshots observe all seven current Sources/editors; each appearance belongs to off-tree staging before a protected map assignment can fail. A parented payload/partial Source state is retained for fresh reconciliation, with an explicit do-not-publish failure. No automatic rollback can overwrite later developer work.

All 15 local catalog/source cases completed and passed: exact real seven-source catalog, owner/place/universe rejection, unrelated paths/classes/new Sources, baseline conflicts, candidate hash/byte changes, duplicate routes, traversal, missing-ID block and exact prepared hash. Receipt: `installer-catalog-validation-final.json`.

Full PNG/package/HTTP validation did not begin successfully: two runs failed during a pinned texture PNG read with FileProvider TimeoutError errno60. No negative HTTP or numeric-package passes are claimed.

After published map IDs are pinned, regenerate the installer/catalog and recheck their hashes against a fresh session-native checkpoint. Actual import, protected template assignment, Studio Play, queues/materials/movement/multiplayer and publication remain unverified here. The published2461 baseline has no Edit preview root; a guarded preservation/retirement step is needed only if fresh inspection finds an owned Ready old preview model.
