# S20 / C04-B12: one unread Exit number literal

Prepared installer only. This directory has not executed Studio/MCP, changed
production Source, written the manifest/index, committed or published anything.
Root owns native execution and the concluding parity/commit. This is a narrow
adaptation of the independently reviewed S18 CAS scaffold, with a parser port in
place of the large native fake-engine gameplay fixture.

The sole source edit removes the 73 LF-byte declaration at line 55:

```luau
local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band
```

The identifier occurs once in the whole source. The initializer is exactly the
number literal `36`: no calls, requires, properties, attributes, constructors,
metatables or event registration. It is not exported or captured. The neighboring
`NO_ANSWER_SECONDS` and `RoundExitPrompt` lines form nonempty, unique forward and
reverse anchors. Everything outside this declaration remains byte-identical.
No runtime feature, API, callback, remote protocol, GUI object or workflow is
removed. Source shrinks from 17,956 to 17,883 LF bytes. No performance gain is
claimed.

Before SHA256: `13b6fdf722449d063204c7e4ee5275d06b7056c78be860a829abc4cee905bae3`.
Candidate SHA256: `bd1cdb46003ae1dd4f151f1c1a0cc7c2ca85ed4add9dd9fe18a27bd765e20752`.

Root's `../native-target-read-v1.json` binds the fresh Source/editor to
`StarterPlayer.StarterPlayerScripts.Round Exit Client`, LocalScript `1_31096`,
parent `1_410029`, enabled/Legacy/Archivable, empty LinkedSource/attributes/tags.
The installer requires these identities and properties again in every native
operation and in the actual `UpdateSourceAsync` callback. Historical repo hashes
are never used to overwrite a different native Source.

## Gate and limits

The exact complete closure and active flows remain in `../REVIEW.md` and the
immutable proposal. The installer pins that proposal and both actual offline
port tools, rechecks all dependency hashes, and runs those actual ports before
the native write and after native export to the repository:

- O0/O1 source compilation, 37 functions in each body; canonical O1 opcode,
  constants, upvalues and child structure equivalence. O0 is not binary identical;
  the original proposal records the different hashes. This is not presented as
  O0 equivalence.
- Whole actual source with actual source dependencies: paired 50/50 assertions,
  fresh-context reentry 50/50, plus timing and duplicate-request mutants rejected.
- The existing unchanged complete B6/B7 neighboring suite: 92 before and 92
  candidate checks. The installed rerun additionally requires the actual repo
  Source and manifest candidate hash/bytes.
- All seven generated native operation variants compile at O0 and O1 (14 checks).

Native `compile` is a parser/factory-return port. It stages **two new unparented
`Instance.new("ModuleScript")` objects**, first verifies exact empty Source/editor,
then writes `return function()\n<whole source>\nend\n` through a fresh SES callback.
`require` must return a function. **That function is never invoked**, so no client
initializer, service lookup, remote or gameplay callback executes. No cloned
LuaSourceContainer, large 445k fixture, borrowed runtime state or mode change is
used. Source/editor/identity/class/properties/attributes/tags of all 213 originals
are checked before, during, after staging, after require, and after cleanup.
Full censuses are followed by a final no-yield check. This is a point-in-time
guard, not a continuous external-edit certificate.

The parser port claims a private shared lease only after a fresh no-yield
compare. Every success and caught assertion/SES/parser failure cleans only exact
owned objects with unchanged name/class/Parent/children and empty or exact owned
Source/editor. Foreign object edits and replaced leases are preserved, with
negative cleanup/lease receipts. A strict host validator requires two created and
destroyed probes, zero remaining probes, all 213 originals unchanged, lease
released, exact factory hashes and zero executed client bodies before passing.

Native CAS is the exact forward/reverse anchor, guarded again inside the callback.
Capture/observe metadata transports at most 20 rows and 20k response bytes.
Native source exports use the actual established reader with 64-line/8k chunks,
target summaries before/after, and an all-original guard after the final chunk.
Only this target's repo file and manifest `sha256`/`bytes` change. Rollback observes
actual native Source and reverses only an exact own candidate; foreign Source or
metadata is retained. File rollback checks attempted operations even if replace
committed and then threw, and reverses only owned fields while preserving foreign
manifest metadata. Temporary files are exclusively created with a unique name;
cleanup checks their handle-captured identity and exact contents. Foreign
replacements/edits are retained. Unique rollback temps prevent a preserved foreign
temp from blocking an otherwise safe rollback. Filesystem guards are immediate
point-in-time comparisons, not an OS-wide continuous transaction.

Each parser call uses one 180-second request. A transport exception can mean a
probe is still running; the installer makes no further native call, retry or
rollback, retains available candidate mirrors/checkpoint/evidence, and reports
pending outcome. Root must reconcile only after fresh evidence that the owned
probe finished and originals/lease are stable. Completed negative parser results
are distinguished from this transport ambiguity and preserve the failure receipt.

Offline engine/player/input/UIDevice/assets/timer/transport/SES/metadata/hash and
parser outcomes are controlled boundaries. Neither offline ports nor native
factory compilation certify gameplay, hardware, multiplayer, streaming,
reserved-server teleport, actual assets or performance.

## Independent reruns

All destinations below must be new; receipts are immutable. The first command
runs the actual filesystem/wrapper/CAS/rollback port against a controlled native
boundary, including six foreign-temp cases and exact post-replace recovery.

```powershell
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v1/test_apply_exit_literal_cleanup.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v1/peer-wrapper-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v1/test_exit_native_cas_guards.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v1/peer-native-guard-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v1/test_exit_parser_faults.py --receipt artifacts/cleanup-20261010/clients-exit-v1/installer-v1/peer-parser-faults-v1.json
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v1/verify_exit_install_proposal.py --receipt-directory artifacts/cleanup-20261010/clients-exit-v1/installer-v1/peer-actual-helper-v1
```

The default `apply_exit_literal_cleanup.py` is an immutable one-shot offline
preparation entry point whose historical receipt already exists; use the
repeatable verifier above for review. `--apply` is Root-only and remains pending
peer review, a fresh scope check, actual native parser before/installed passes,
verified export, console/diff checks, final full parity and commit:

```powershell
python -B artifacts/cleanup-20261010/clients-exit-v1/installer-v1/apply_exit_literal_cleanup.py --apply
```

`build_scoped_installer.py` and `build_offline_tests.py` retain the initial adaptation
seed for provenance. They use exclusive writes and cannot overwrite these final
reviewed artifacts. Manual gate/ownership corrections after the seed are recorded
by the frozen file pins; the seed is not the final installer generator.

Earlier intermediate PASS receipts are retained separately. Final receipts and
the preserved fixture-development failures are listed by `frozen-pins-v1.json`.
