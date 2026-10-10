This is a prepared readonly cache-inventory port. It has made **zero Studio/MCP
calls, native Instance/Source/property writes, production edits or index writes**.
Root alone may execute it after independent review against a fresh Edit session.

The exact selected roots are the uniquely named ServerStorage
`MongoTVEntityAnimations` Folder with 117 direct children and `RBX_ANIMSAVES`
Model with 27 direct children. Begin captures their actual native identities,
parents, classes, names, Archivable, attributes, tags and exact child identities.
Every guard also rejects a newly introduced same-name root collision. No old
root instance ID or source hash authorizes the read against a newer session.

The collector traverses each selected forest with yields every 1,000 nodes. It
reads classes and the two cache-ID attributes to discover every direct child,
AnimationClip, Animation, PublishedAssetId/AnimationId-bearing instance, and
named PublishedAssetId/AnimationId ValueBase. It records complete attributes,
tags, class, identity, path, parent, Archivable, child count, typed ID fields,
Animation.AnimationId and KeyframeSequence Loop/Priority/AuthoredHipHeight on
those candidates. All actual names and versions are retained; the optional
publisher-version inference is explicitly derived and never filters records.
Class histograms, actual node/descendant counts and candidate-identity hashes
accompany each root. No v10 fixture or fixed eight-published-ID list bounds the
native capture. Unknown attribute datatypes fail rather than silently vanish;
an unreadable property is explicit incomplete metadata, never a nil certificate.

Begin and finish independently re-discover the targeted candidate set, with
yields every 1,000. This detects new nested ID attributes/Animation candidates
and changed discovery/count/class coverage. **Pages never repeat the whole
forest traversal.** Pages compare the cached 213 original sources and selected
metadata refs. Full fresh Source catalog traversals at begin, after capture and
finish check count, exact Source/editor agreement, identity, class, Enabled,
Disabled, RunContext where applicable, Archivable, LinkedSource, attributes,
tags, paths and child counts. Sources are read and compared; no script body is
required, loaded or executed. No test Instance is created.

Scratch state is an ephemeral purpose-bound shared namespace with two exact
ownership slots. Bound closures retain original table identity and progress;
copied/replaced slots or foreign progress refuse cleanup and remain pending.
Setup/page/cleanup namespace and protocol state writes are counted separately
from native object writes: 2 + pageCount + 2 for a completed capture. Fallible
cache reads have ownership and cleanup installed beforehand. Known collector
failures clean only exact owned scratch; foreign scratch is preserved. No
listener, spawned task or connection is created. `task.wait()` only yields the
current operation. A local transport close does not cancel a native operation.

The manifest is capped at 10,000 records and 10,000,000 UTF-8 bytes. It is split
into deterministic 12,000-byte chunks, base64 encoded to avoid UTF-8 split loss,
and every collector response is capped at 20,000 bytes. This stays below the
native proxy's reported 100,000-character response truncation. Root driver
archives each request/code hash, bounded raw MCP envelope, raw completion,
chunk bytes, chunk hash and complete manifest. A response envelope over 100,000
bytes is recorded by size/hash **without a whole-envelope archive** and refuses
the capture. Whole envelopes within the bound are retained before validation.

Each operation is a single `_request(timeout=600)`. Unknown transport or invalid
completion stops every later native call, retry and automatic abandon. It
records pending scratch; Root must reconcile from fresh evidence after the
in-flight operation is known to have stopped. Synchronous completed tool errors
are distinguished but likewise do not trigger automatic native recovery. A
fully received manifest is followed by known finish/guards/owned cleanup before
local completeness validation; incomplete metadata then refuses preservation
certification with cleanup known closed. All other refusal evidence is kept.

The actual collector offline port passes **56 cases / 366,487 checks**. It
includes all four synthetic versions, multi-page success, Source/editor/class/
property/identity/attributes/tags drift, initial and later root collisions,
cache/Animation/sequence/value metadata drift, new nested ID/Animation/Source
coverage, exceptions during traversal, all bounds, deterministic page order,
owned abandon, occupied/foreign namespace/progress preservation and explicit
unreadable property metadata. The actual Root driver port passes **27 cases**,
including unknown-before/after begin/page/finish, completed tool errors,
malformed/oversized envelopes, invalid pages, metadata refusal after owned
cleanup and known cleanup-versus-pending collector failure. Neither port calls
Studio. Table-backed game/Source/editor/task/shared/Encoding/JSON/transport
boundaries do not prove native scheduling, actual cache contents or cancellation.

This is a targeted metadata/cache-preservation manifest, **not a full native
asset archive, serialized-reference proof or deletion test**. Other pose and
keyframe properties/attributes are not inventoried. Every non-cache asset value
still requires a full off-place native archive and restoration/reference gates.
Point-in-time equality guards cannot prove continuous actor provenance or
absence of an edit-and-restore between observations. No native gameplay,
multiplayer, streaming, reserved-server, performance or memory/FPS gain is
claimed. No upload, re-upload, CreateAsset, Serialize/Deserialize, delete,
publishing or Play-mode operation exists in this package.

Independent offline replay, writing only a new receipt:

```powershell
python -B artifacts/cleanup-20261010/animation-cache-inventory-v1/test-offline.py --receipt artifacts/cleanup-20261010/animation-cache-inventory-v1/ROOT-offline-review-v1.json
python -B artifacts/cleanup-20261010/animation-cache-inventory-v1/run-root-inventory.py
```

Root-only native command after a pinned independent receipt containing
`preparationEligibleForNativeRead=true`, `nativeExecuted=false`,
`deletionApproved=false`, exact `reviewedCollectorSHA256` and
`reviewedDriverSHA256`:

```powershell
python -B artifacts/cleanup-20261010/animation-cache-inventory-v1/run-root-inventory.py --apply --studio-id FRESH_EDIT_SID --peer-review EXACT_PEER_JSON --peer-sha256 EXACT_PEER_SHA256 --run-directory artifacts/cleanup-20261010/animation-cache-inventory-v1/native-run-v1
```

Do not retry that command or reuse a run directory after a transport ambiguity.
An actual completed Root report and fresh parity are still pending. All exact
raw input/output pins are in `frozen-pins-v1.json`.
