# S18 C06 Level4PreviewPrompt: scoped installer review

Status: preparation completed; parent-owned Studio installation and installed native port pending. This agent made no Studio, production Source, manifest, index, commit, Play-mode or publish writes.

The sole proposed source change removes the 215-byte special-player conditional, two nil-to-nil assignments and stale comment in `StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua`. The fresh local plain `PROMPTS` literal contains only the two Level 4 keys; neither removed Level 6 key exists and no intervening code writes them or adds a metatable. All other source bytes remain exact. No feature, filter, API, remote, connection or callback is removed. The ordinary Legacy LocalScript domain has an engine LocalPlayer and scalar UserId; a missing LocalPlayer or throwing synthetic UserId getter is outside that certified domain. This is not a gameplay, multiplayer, streaming or performance certificate.

The frozen target is `StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt`, LocalScript `1_31106`, parent `1_410029`; Enabled=true, Disabled=false, RunContext=Legacy, Archivable=true, LinkedSource empty, no attributes/tags. Before: 1622 LF bytes, SHA256 `161206ea81938d5a10408bc85f6c2b027c37015cc51378b3d721cbb8323c4436`. Candidate: 1407 bytes, SHA256 `e024ae800bea7082e72a590e948c0b54e9db503db70ef24e50f51024726ad4d3`. Exact anchors and their inverse are held in `preview_noop_source_cas.luau`; neither anchor is empty and each must occur exactly once.

The installer binds the immutable actual Root receipt `../native-before-result-v1.json`, using `rootExecutedCodeSHA256`, directly to the reviewed `native-binding-v1/native-before.luau`. Root recorded 455 checks/version, 910 paired and 910 reentry checks, four fresh owned ModuleScripts created/destroyed, all 213 original Source/editor records unchanged, zero original writes and zero mode switches. Its recorded 33.875 seconds is the native-before client call duration, not a measured performance gain. It does not certify live gameplay. The installed contract uses `native-binding-v1/native-installed.luau` and the same strict coverage/cleanup/write/semantic-negative gates.

Native mutation rechecks mode, exact identity, class, source/editor and properties/attributes/tags for the target and all 213 originals. The exact Source baseline is rechecked inside the UpdateSourceAsync callback before the one-anchor transform. Metadata exports use 20 rows/20 kB pages; actual Source export uses the established reader with 64 lines/8 kB bounded responses. Repo mirror parity must match all 213 sources before and after, while only the target manifest row's `sha256` and `bytes` fields may change. HEAD, console snapshots, identities and other sources are preserved and rechecked. A private checkpoint holds the original source, working/HEAD manifests, native source/editor and generated native operations.

Recovery observes the actual current Source and manifest owned fields. It handles an `os.replace` that commits and then raises or whose post-read loses a race; completed own candidates are restored, unrelated manifest metadata is retained, and foreign source/target fields are preserved for reconciliation. A completed negative native contract triggers controlled recovery. Installed execution uses one `_request(timeout=180)`, bounded result text and no retry. If that request throws, its probe might still be running: the installer records an unknown pending outcome and preserves its own candidate native/source/manifest without another native query or rollback. Root must establish released probe ownership and stable originals before further action.

Offline receipts:

- `offline-wrapper-tests-v3.json`: PASS 34 actual wrapper/filesystem/CAS/recovery cases, 260 assertions; all native/MCP/console/git boundaries are controlled. Includes five actual post-replace fault injections and nine installed-result/transport integration cases. Seven strict actual-before-receipt validator cases and the actual unique-anchor forward/inverse transform's five cases/eight assertions and O0/O1 compilation pass additionally. Canonical Source/manifest unchanged.
- `native-guard-tests-v1.json`: PASS 15 actual generated Luau identity/guard/transform/callback cases, 75 assertions and O0/O1 compilation. Engine metadata, JSON, known-body hashing and callback scheduling are explicit table boundaries; this is not a real ScriptEditorService or native platform certificate.
- `offline-proposal-v1/proposal.json`: twelve generated native capture/observe/target/verify/apply/rollback O0/O1 compiles. The template is unchanged since this receipt. Its historical pending wording predates the actual Root-before receipt.
- All four final Python tools parse successfully. The initial failed temporary fixture and earlier immutable receipts are preserved as history; v3 and `frozen-pins-v1.json` identify the final integration state.

Parent command after independent peer review:

```powershell
python -B artifacts/cleanup-20261010/clients-next-v1/cas-v1/apply_preview_noop_cleanup.py --apply
```

Private destination: `.git/mongotv-cleanup-20261010/preview-source-install-v1`. Public result destination: `artifacts/cleanup-20261010/clients-next-v1/preview-source-install-v1`. Both must be fresh and are never overwritten. Default proposal and existing immutable test receipt paths also must not be rerun blindly; use the test wrapper's explicit fresh `--receipt` for independent reruns. No Studio-mode switch, publish, push or bulk synchronization is included.
