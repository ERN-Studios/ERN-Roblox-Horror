# One new LobbyCeilingSweeps LocalScript

Prepared code only. No Studio, runtime mirror, or production manifest has been changed by this task. The owner currently asked for code work without UI; keep these commands for root's later authorized installation. This package does not start/stop Play, save or publish.

The only target is `StarterPlayer.StarterPlayerScripts.LobbyCeilingSweeps`, class **LocalScript**, mirrored as `StarterPlayer/StarterPlayerScripts/LobbyCeilingSweeps.LocalScript.lua`. Both dry-run and apply require **PlaceId 131311258779917 / GameId 10559217407**, including checks again after a source-update yield; actual IDs are returned and checked by the host verifier. It embeds the exact reviewed source: **6,847 canonical UTF-8 bytes**, SHA-256 `235a26d42b0d0ee80de5768bc3da428a1296aa73f9d08967594476ae129f2198`. No lamps, existing controllers or unrelated scripts are installed or replaced.

At preparation, the actual sync manifest contains **125 scripts +14 RemoteEvents =139 items**, and neither this target entry nor mirror file exists. Adding only this script gives **126 scripts /140 total items**. `prepare_install.py` and the finalizer derive counts from actual entries; these are observations, not fixed numbers to force after other changes.

## Root's exact installation sequence

1. Remain in **stopped Studio Edit**. Read `install-edit.luau` in full and pass its contents unchanged to `mcp__Roblox_Studio__execute_luau` with `datamodel_type="Edit"` and root's verified current `studio_id`. The file defaults to `local APPLY = false`; this preflight does not create instances or change sources/Enabled state. It must report `would-create`, `would-enable-exact`, or `already-exact`. Do not infer native target absence from the artifact's filesystem inventory.
2. After the dry run matches the intended place and path, call the same tool with the exact same file contents except **replace the single `local APPLY = false` with `local APPLY = true`**. No other substitutions are required: the source is embedded, so there is no XML import, content-folder copy, external fetch or payload instance. The entrypoint itself refuses live Play, including rechecking after `UpdateSourceAsync` yields. Save the returned decoded JSON report as `installation/studio-apply-readback.json` (the report object containing actual `Source`, not the outer MCP response wrapper).
3. The installer creates a new LocalScript **disabled before parenting and source update**, writes with `ScriptEditorService:UpdateSourceAsync`, rechecks identity and actual `.Source`, then enables it. Already exact and enabled means a zero-write idempotent result; exact but disabled may be safely enabled after verification. Wrong class, duplicate name or conflicting source aborts without replacing or deleting anything. A failure after new creation leaves only that new object disabled for inspection. A lost response can be retried: only a fully exact disabled landing will be enabled. A partial/conflicting landing remains a conflict.
4. Verify the actual readback using the shared repo contract. This command writes only an artifact candidate and prints the intended counts:

   ```powershell
   python artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/finalize_verified.py --readback artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/studio-apply-readback.json
   ```

   The host uses **`tools/studio_source_contract.py`** `classify`, `canonical_bytes` and `sha256_of`. CRLF is normalized to LF; no new trailing-newline exemption is invented. The Luau installer performs exact canonical string comparison, **not a fabricated SHA-256 calculation**; the host hashes the independently returned source. Its candidate has `status="synced"` only after a successful Edit apply report, correct native path/class, enabled state and exact actual source are verified.
5. Inspect the one-entry addition in `manifest-after-verification.candidate.json`, then root may register the verified mirror and manifest with:

   ```powershell
   python artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/finalize_verified.py --readback artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/studio-apply-readback.json --apply
   ```

   This reads the **current** manifest again, preserves all its existing entries, computes counts from entries, preserves the actual trailing-newline metadata, and backs up the manifest inside this artifact folder. It exclusively creates the one mirror file; an existing conflicting mirror or manifest entry is refused. An already synced exact mirror/entry is a no-op. If a concurrent manifest change is detected after mirror creation, it leaves the verified mirror for an idempotent retry rather than deleting content. Do not copy the old full candidate manifest over a newer checkpoint.
6. Root performs the normal full-source compile/audit and verifies the new source from actual Studio again before native acceptance. Use the existing `../NATIVE-RUNBOOK.md` and `../native-readonly.luau` for the real lobby effect/Party/accessibility/lifecycle acceptance. Only after the feature's native final critique passes does root publish separately with the mouse and record the actual version. A bootstrap result is not native behavior or publication evidence.

The standard tools cannot create this unknown target: `record_pending_push.py` explicitly reports new mirrored scripts as UNKNOWN, and the push tool expects a pre-existing manifest/Studio object. Do not add an unverified synced entry merely to make the normal push accept a nonexistent script.

## Bounded offline verification

```powershell
python artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/prepare_install.py
python artifacts/trello-20260909/lobby-ceiling-sweeps-prepared/installation/test_install.py
```

**64 actual-bootstrap checks +26 host verification checks and two whole-file compiles pass.** The host executes the actual generated installer against recording instances and UpdateSourceAsync callbacks. It covers dry-run nonmutation, new creation ordering, callback retry, exact enabled/disabled idempotence, CRLF, wrong place/universe in dry-run and apply, wrong parent/class/source, duplicate names, forbidden extra LF, wrong execution context, pre/post-write failures, readback mismatch, Play beginning during write, duplicate appearance and an occupied callback. Failed new objects are preserved disabled.

Host verification tests execute the real contract-based `verified`/`plan` functions with the current manifest and controlled reports, including refusal of failed/wrong-class/wrong-source/disabled readbacks, mirror/manifest conflicts, duplicate identities, unchanged existing entries and correct counts. They do not call Studio or `--apply`, and do not claim to simulate the full editor engine or OS crash atomicity. Native existence/readback remains root's installation step.

Independent reviewer `audio_readiness` awarded **9/10**, reran all 64+26 checks and both compiles, and verified exact template expansion and the manifest delta. See `independent-review.md` and `independent-validation.json`. Reviewed bootstrap SHA-256: `652e8f3255a337af4691d2a24dae1fb01df7951bb50e3131829dc054274b1a38`. This is installation-code acceptance; no native installation, feature acceptance or publication has occurred in this task.
