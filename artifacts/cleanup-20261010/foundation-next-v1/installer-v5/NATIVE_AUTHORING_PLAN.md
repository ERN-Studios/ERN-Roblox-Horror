# Root-owned authoring port — pending, no execution by this candidate

This port covers the generic installer's authoring contract on new owned native
objects. It is not a gameplay, multiplayer, streaming, asset-restore or
performance test. Production `tools/install_new_scripts.py` remains unchanged.
The candidate is not approved for promotion by the offline receipts.

## Fresh baseline and bounded ownership

1. Root finishes any current native batch and obtains a fresh Studio inventory,
   Edit state, console and native catalog. Pin the chosen Studio GUID, PlaceId
   `131311258779917` and UniverseId `10559217407`. Do not switch modes. Abort
   before creating anything if Studio is in Play, the native identity differs,
   any Source/editor conflict exists, or a different native probe lease is held.
   A stale historical catalog or old pending-push flag is not a write baseline.
2. Capture all current authoritative LuaSourceContainers by native instance
   reference and debug ID: full path, parent reference/ID, class, raw Source and
   editor Source, Enabled/Disabled/RunContext where applicable, Archivable,
   LinkedSource, attributes and sorted tags. Also capture relevant non-script
   original parents. The last verified project had 213 scripts; use the fresh
   inventory, and stop rather than treating an unexpected count as approved.
   Save bounded metadata pages and a canonical catalog hash locally.
3. Acquire a new nonce-owned in-memory probe lease and create one **fresh
   Folder** under ServerStorage named `__CleanupInstallerAuthoring_<nonce>`.
   Record the exact folder reference, debug ID, parent and empty baseline.
   All test targets must be direct descendants of this folder. No original
   instance is a writable target. No LuaSourceContainer is cloned.
4. Use a new local temporary project with the pinned candidate/helper files,
   a synthetic manifest, and mirrors only for those owned paths. Pin the real
   Studio GUID in the Root test adapter. The adapter must reject an arbitrary
   or newly active same-name Studio rather than following the general selector.
   No real repo mirror or manifest is mutated by this port.

## Actual generated payload and all-original guards

Execute the candidate's actual `lua_lookup`, `lua_create`, `lua_update`, S13
metadata generator and bounded source reader. Record exact generated payload
hashes before execution. Use no `require` or runtime execution of test Source.
Small test Source is a harmless return literal with Danish/emoji text.

A lexical wrapper around each generated payload supplies two test adapters;
it must not mutate global `Instance` or replace a Studio service:

- `Instance.new` delegates to real native `Instance.new("ModuleScript")`,
  asserts exact empty Source/editor, records the fresh reference/ID in the
  lease's owned registry before returning it, and rejects other classes.
- A local SES proxy delegates reads and `UpdateSourceAsync` to the real SES.
  Before invoking any write it checks the exact owned object/reference and
  parent/slot, the lease, Edit/place/universe, and **all authoritative original
  guards**. The delegated callback checks those originals again immediately
  before the candidate callback. Guard checks are repeated after both success
  and failure, and after cleanup. Count write attempts and returned successful
  native callbacks separately. Native adoption/cleanup is not inferred from
  an offline fake or a transport timeout.

The generated payload locally binds its own SES variable, so an outer lexical
variable alone cannot intercept it. The Root wrapper must replace the exact
expected SES binding site(s) with the lexical proxy, assert the replacement
count, and retain the unmodified generated payload as a separately pinned
artifact. Do not silently substitute a different resolver or metadata body.

The wrapper is fault injection only. The candidate path resolver, metadata
capture, Source hashes and callback guards remain its actual generated code.
Record the unwrapped payload and wrapped execution-code hashes separately.
The wrapper and receipt validator need independent review before Root executes
this plan. This document does not constitute that review or a native pass.

## Small port matrix

| Case | Concrete action | Required observation |
| --- | --- | --- |
| Create | Actual main creates a missing `ModuleScript` in the owned folder from exact empty Source/editor. | One adopted fresh ModuleScript, one scoped successful callback, exact Source/editor and native metadata; actual synthetic manifest registration preserves unrelated queued rows and unknown fields. |
| Same Source | Rerun actual main for that owned target with matching Source. | Zero additional native Source writes; fresh S13 metadata registered, stale manifest metadata refreshed. |
| Refuse differing Source | Change only the local owned mirror and run actual main without overwrite. | Failure/DIFFERS, zero Source writes, unchanged owned native Source and synthetic manifest. |
| Scoped overwrite | Capture current owned native baseline and run actual main with overwrite. | Candidate native metadata/identity/property/attribute/tag/Source/editor checks pass before and inside callback; one exact landing and fresh downstream metadata. |
| Callback property conflict | In the SES proxy's delegated real callback, change **only the owned test object's** Archivable before calling the actual candidate callback. | Candidate refuses before returning replacement Source; actual previous Source/editor and the conflict property are preserved. No synthetic manifest registration. This is controlled native property fault injection, not evidence of a real concurrent Studio schedule. |
| Wrong class / create race | A separately recorded fresh owned Folder occupies one missing target slot before payload execution. | Actual generated create preflight rejects, does not allocate a replacement or destroy the occupying Folder; main class validation likewise rejects before Source mutation. |
| Commit then error | For a separate freshly adopted ModuleScript, the local SES proxy delegates the real update successfully and then throws. | Candidate reports failure and cleans only the exact still-owned object. All originals match; successful native write count and cleanup count are recorded separately. No retry or old-original restoration. |

Use a valid Windows Unicode mirror filename such as `Prøve 😀.ModuleScript.lua`.
The preserved offline native path matrix separately covers quotes in names;
Windows cannot create a mirrored filename containing `"`.

## Cleanup and acceptance

Root checks exact owned reference/ID, Source/editor, tracked properties,
attributes/tags, parent/slot and lease before destroying each remaining probe.
The property-conflict case records its deliberate owned property mutation as
part of its test state. Reconcile that known test mutation by a fresh exact
CAS before cleanup, or include the known final value in the owned cleanup
baseline. This is not authority to restore an original or a foreign edit.
If a probe is foreign-modified, moved, or unreadable, preserve it and report the
exact remaining owned reference/ID; do not clear an unknown lease or delete by
name. Destroy the owned folder only after all expected owned objects are gone,
it remains the exact owned folder, and it contains no foreign descendants.
Release only this nonce's lease. Verify all original guards again even if a
callback, an assertion, a getter or cleanup fails.

Accept only a complete returned native receipt with exact code provenance,
before/after all-original catalog equality, unchanged native original Source,
parent/properties/attributes/tags, no mode switches, no runtime state borrowed,
correct case/write counts, zero remaining probes, zero cleanup errors and the
lease released. Compare console before/after and report pre-existing output
separately. A transport timeout or unknown return is **pending**: no automatic
retry, guessed success, bulk cleanup, or blind rollback.

Native editor-draft conflict, editor identity, all three creation classes and
large single-literal write transport remain separate pending checks. The
small ModuleScript port must not be reported as certifying these. Large reads
have an offline measured 64-line/8k response bound, but the tested 91,702-byte
overwrite still sends a 99,637-byte request; bounded write transfer is not
implemented or certified. There is no performance improvement claim.
