# V6 pending candidate; V5's combined ownership gate failed

The peer-composed V5 Parent setter sequence **commits, detaches, then throws**
was executed against the actual generated create payload. Its expected
preservation assertion fails: `attached` remained false, so the unparented
owned object was destroyed. V5's earlier separate commit-error and detach
fixtures passed but did not certify this combined state. All V5 code, old
receipts, frozen pins and curation remain unchanged. Do not describe V5 as an
overall ownership pass or promote it.

V6 marks **attachmentAttempted before the Parent setter**. Once it is attempted,
nil Parent is an unknown outcome and is preserved. A still-exact owned
parent/path/slot with known Source/editor/properties can still be cleaned.
A setter that throws before its mutation and a commit/detach/throw have the
same observable nil Parent, so the former fixture now also deliberately
preserves the allocation. This trades an explicit retained unknown test
object for unsafe destruction. No authoritative object or original Source
is restored or destroyed.

The previous expanded actual-main/generated suite passes unchanged counts:
312 Python checks;14 previous main cases/86 fixture checks;29 added main
cases;711 generated cases/2241 checks/14 O0/O1 compiles;old production20
Unicode checks. Real local atomic suite passes15 cases/91 checks.
The separate actual generated combined port passes **138 cases/432 checks**
on V6; its V5 negative receipt records the real failed preservation assertion.
Native/hash/JSON/scheduler boundaries remain explicit fakes.

The first V6 combined driver failed before any payload ran because it expected
the old `detached-own` branch spelling. The setup failure and first driver
remain preserved; V2 adapts the fixture branch without altering candidate
code. This setup failure is not a candidate pass or native evidence.

V6 remains candidate-only. The V5 native authoring plan's scope/independent
wrapper review, real SES/editor identity, native creation classes and large
single-literal transfer are still pending. Large write/read limits and
ordinary OS CAS/check-use windows remain unchanged. Unknown retained objects
must not be represented as successful zero-probe cleanup.

The exact V5 failure and V6 result are stored in the separate
`foundation-parent-cas-v1` directory. No production/native/manifest/index or
commit write was made by this task. Root owns any eventual integration.
