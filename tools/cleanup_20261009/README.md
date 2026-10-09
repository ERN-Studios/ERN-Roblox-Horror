# Diagnostic Folder archive verification

The verify/test tools handle only the twelve historical PipeEntity diagnostic
Folder names pinned in `diagnostic_folder_archive.luau`. They never connect to
Studio, read authentication cookies, remove instances, or write input archives.

Run the Luau commands from the repository root. Use a **new** receipt path every
time: existing files/directories are refused. The verified portable interpreter
for this task is `%TEMP%/codex-lune-0.10.5/lune.exe`, from the official
[Lune v0.10.5 release](https://github.com/lune-org/lune/releases/tag/v0.10.5).

```powershell
$cleanupLune = "$env:TEMP/codex-lune-0.10.5/lune.exe"
$cleanupArchive = "artifacts/cleanup-serverstorage-20261009/diagnostic-archive-before-v4"
& $cleanupLune run tools/cleanup_20261009/verify_diagnostic_folder_archive.luau "$cleanupArchive/facts.json" "$cleanupArchive/native.rbxm" artifacts/cleanup-serverstorage-20261009/folder-verification-NEW.json
& $cleanupLune run tools/cleanup_20261009/test_diagnostic_folder_archive.luau "$cleanupArchive/facts.json" "$cleanupArchive/native.rbxm" artifacts/cleanup-serverstorage-20261009/folder-tests-NEW.json
python -B tools/cleanup_20261009/verify_diagnostic_folder_references.py --lune $cleanupLune --archive $cleanupArchive --receipt artifacts/cleanup-serverstorage-20261009/reference-verification-NEW.json
python -B tools/cleanup_20261009/test_diagnostic_folder_references.py --lune $cleanupLune --archive $cleanupArchive --receipt artifacts/cleanup-serverstorage-20261009/reference-tests-NEW.json
```

`facts.json` uses schema `folder-diagnostic-archive-v1`, fixed place/universe IDs,
nativeSHA256/nativeBytes, and twelve roots with name/class/archivable/tags/typed
attributes/children=0. Optional properties are Sandboxed, IconTint RGB components,
and the empty Capabilities string. Unknown attribute/property types and nonzero
capabilities fail closed. Lune's native DOM preserves IconTint/Capabilities even
though its Lua property getters cannot expose them; verification reads these two
values from each zero-child Folder's serialized XML and reopens the native forest.

The separate reference gate requires referencesSHA256/referencesBytes and
`references.rbxm`: one joint serialization of the same twelve roots plus
StarterPlayer. Real XML parsing checks every serialized Ref, including protected
PlaceAvatarRules; source CDATA and comments cannot invent references. Referent IDs
are compared only within this joint serialization. The native folder and reference
gates remain separate so each retains its original archive digest.

These receipts prove local decode/re-encode/reopen and reference absence at
capture time. They do not certify all live Instance references, gameplay,
performance, a full-place restore, or deletion. A future removal still requires
fresh authoritative originals, live readable-reference/selection checks, accounted
protected nonserialized fields, and a joint-reference guard that detects later
property-only changes immediately before removal. Preserve raw archives and do
not recreate them from historical repository Sources.

`storage_record_archive.py` is a separate live, read-only export wrapper. It
requires existing Edit and HttpEnabled=true, transfers native bytes through a
loopback-only receiver, and never switches modes or changes game settings.
`capture_storage_records.luau` keeps owned session references for later CAS;
it does not delete or rewrite authoritative objects. `probe_storage_records.luau`
uses fresh unparented test Folders and independent cleanup/final original guards;
it does not remove the original records. Its native reconstruction remains
pending while another session is in Play.

`retire_absent_codex_mirrors.py` performed the separate S02 repo-only batch:
ten exact stale mirrors already absent from native were archived byte-exact
outside mirror roots and removed from the downstream manifest/files. Its
immutable archive destination now exists, so re-running intentionally refuses.
