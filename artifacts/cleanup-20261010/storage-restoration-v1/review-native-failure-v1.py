"""Independently verify recorded native failure; never invokes Studio or receiver."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
RUN = HERE / "native-v4-run-v1"
sha = lambda raw: hashlib.sha256(raw).hexdigest()
checks = 0

def check(value, label):
    global checks
    assert value, label
    checks += 1

def read(name):
    return (RUN / name).read_bytes()

def decode(name):
    return json.loads(read(name))

def pin(path):
    check(path.is_file() and not path.is_symlink(), "Pinned evidence must be a regular owned file")
    raw = path.read_bytes()
    return {"path": path.relative_to(ROOT).as_posix(), "bytes": len(raw), "sha256": sha(raw)}

frozen = json.loads((HERE / "file-pins.json").read_bytes())
for row in frozen["files"] + frozen["historicalInputs"]:
    raw = (ROOT / row["path"]).read_bytes()
    check((len(raw), sha(raw)) == (row["bytes"], row["sha256"]), "Frozen source/historical input changed")
probe_raw = read("probe-root-completion.json")
base_raw = read("baseline-root-completion.json")
probe, base = json.loads(probe_raw), json.loads(base_raw)
for phase, raw in (("probe", probe_raw), ("baseline", base_raw)):
    api = decode(phase + "-root-api.json")
    check(api["result"]["isError"] is False, "Native API transport failed unexpectedly")
    texts = [row["text"] for row in api["result"]["content"] if row["type"] == "text"]
    check(len(texts) == 1 and texts[0].encode() == raw, "Root receipt must equal actual native API text")
    provenance = decode(phase + "-root-provenance.json")
    check(provenance["completionSHA256"] == sha(raw) and provenance["actualNativeResponse"] is True
          and provenance["noRetry"] is True, "Actual response provenance mismatch")
    check(provenance["executedCodeSHA256"] == sha(read(phase + "-source.luau")), "Actual executed source pin mismatch")
    posted = decode(phase + "-root-post-result.json")
    check(posted["status"] == 200 and posted["body"] == "saved" and posted["sentActualCompletionSHA256"] == sha(raw),
          "Receiver was not given the actual completion")
check(read("probe-native-completion.received.json") == read("probe-native-completion.json") == probe_raw,
      "Receiver copies must retain exact native failure bytes")
check(read("live-baseline-native-completion.json") == base_raw, "Native baseline bytes changed")
verdict = decode("port-verdict.json")
check(verdict["recipePassed"] is False and verdict["restorationCertified"] is False
      and verdict["normalizationApplied"] is False and verdict["completionSHA256"] == sha(probe_raw), "Failure was certified")
check(base["pass"] is True and base["originalSourcesUnchanged"] is True and base["liveSources"] == 213
      and base["liveRoots"] == 52 and base["liveDescendants"] == 416284, "Actual fresh native baseline inconsistent")
check(base["watchers"] == base["watchersReleaseAttempted"] == 534, "Readonly watchers incomplete")
check(sha(read("live-baseline.json")) == base["baselineSHA256"] == probe["liveBaselineSHA256"] == verdict["baselineSHA256"],
      "Native baseline hash chain broken")
live = decode("live-baseline.json")
check(len(live["sourcePins"]) == len({p["path"] for p in live["sourcePins"]}) == 213, "Fresh Source pin census inconsistent")
check(len({p["identity"] for p in live["sourcePins"]}) == 213, "Ambiguous fresh Source identities")
check(probe["schema"] == "external-held-storage-native-restoration-supplement-v4" and probe["pass"] is False,
      "Unexpected native recipe verdict")
check("Bone setter changed exact components" in probe["error"] and "function restoreFourCFrames" in probe["error"],
      "Failure location does not match the scoped setter assertion")
check(probe["testOwnedCFrameSetAttempts"] == probe["testOwnedCFrameWrites"] == 1, "Unexpected setter attempts")
check(probe["createdRoots"] == probe["adoptedRoots"] == probe["destroyedRoots"] == 23
      and probe["testOwnedRootsRemaining"] == 0 and probe["copyAdoptionErrors"] == [], "Copy cleanup incomplete")
for key in ("originalNativeArchiveUnchanged", "originalSourcesUnchanged", "originalSourcePinsUnchanged", "leaseReleased"):
    check(probe[key] is True, "Failed authoritative final guard: " + key)
check(probe["freshSourcePinsValidated"] == 213 and probe["knownOriginals"] == 430364 and probe["watchers"] == 28738,
      "Unexpected native protected identity/source/watch scope")
check(probe["normalizationApplied"] is False and probe["restorationCertified"] is False
      and probe["removalAttributedToCleanup"] is False, "Native recipe widened its scope")
for key in ("sourceWrites", "originalParentWrites", "modeSwitches"):
    check(type(probe[key]) is int and probe[key] == 0, "Unexpected authoritative writes: " + key)
check("secondSupplementedReopenPass" not in probe and "supplementPasses" not in probe,
      "Later recipe stages unexpectedly claimed complete")
for name in ("roundtrip.rbxm", "transfer-receipt.json", "roundtrip-part-0000.bin"):
    check(not (RUN / name).exists(), "Premature transfer unexpectedly exists")
source = read("probe-source.luau").decode()
assertion = 'check(copy.CFrame==wanted and canonical({copy.CFrame:GetComponents()})==canonical(spec.components),"Bone setter changed exact components")'
check(source.count(assertion) == 1 and source.index("copy.CFrame=wanted") < source.index(assertion), "Actual failed assertion changed")
supplement = decode("restore-supplement.json")
inputs = decode("inputs.json")
check(inputs["inputs"]["probeSource"]["sha256"] == sha(read("probe-source.luau"))
      and inputs["inputs"]["baselineSource"]["sha256"] == sha(read("baseline-source.luau")), "Immutable receiver source pins mismatch")
check(inputs["inputs"]["native"]["sha256"] == "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca",
      "Historical original archive pin changed")
evidence = [pin(p) for p in sorted(RUN.iterdir()) if p.is_file()]
result = {"schema": "storage-restoration-native-failure-independent-review-v1", "reviewer": "storage_next",
    "readOnlyReviewPassed": True, "reviewChecks": checks, "nativeCallsByReviewer": 0,
    "recipeStatus": "afventer test — native V4 exact setter gate failed", "recipePassed": False,
    "authoritativeRegressionDetectedByRecordedGuards": False, "nativeDeletionApproved": False,
    "restorationCertified": False, "normalizationApplied": False, "expandedSetters": False,
    "actualResultAtUtc": probe["capturedAtUtc"], "nativeChecks": probe["checks"],
    "failure": {"assertion": assertion, "firstOwnedSetterAttempt": True, "assignmentReturned": True,
        "exactSetterVerificationPassed": False, "componentDeltasRecorded": False,
        "equalityPredicatesRecordedSeparately": False, "normalizationCauseEstablished": False,
        "inferredFirstTargetFromPinnedArray": supplement["rows"][0]["path"],
        "targetWasNotRecordedInNativeCompletion": True,
        "limit": "The combined CFrame equality/12-component predicate failed. Receipt does not determine which predicate or component differed; old DS R21 diffs are not new after-setter evidence."},
    "completedScope": {"freshNativeSourcePins": 213, "knownOriginalIdentities": 430364, "createdRoots": 23,
        "adoptedRoots": 23, "destroyedRoots": 23, "remainingOwnedRoots": 0, "setterAttempts": 1,
        "setterAssignmentsReturned": 1, "leaseReleased": True, "originalNativeArchiveUnchanged": True,
        "originalSourcesAndPinsUnchanged": True, "sourceWrites": 0, "originalParentWrites": 0, "modeSwitches": 0},
    "unfinishedScope": ["Exact first setter verification", "remaining three first-reopen setters",
        "whole supplemented readable forest/reference/source and raw binary comparison",
        "second reopen/four setters/second serialization", "complete recovery recipe", "native deletion gate"],
    "diagnosticProposalOnly": {"preparedExecutable": False, "executed": False,
        "scope": "At most one fresh unparented Bone and the four pinned wanted CFrames; never use DS/retry V4, an original Bone, original property setters, cloned scripts or a live parent.",
        "observations": ["Capture all12 expected/wanted/after components plus exact %.17g strings",
            "Record CFrame equality and component equality separately, and exact differing indices",
            "Fresh all213/held-native guards, cleanup on both success and throw, zero test-owned instances remaining"],
        "interpretation": "A mismatch on a fresh Bone would isolate the generic setter path; a match would leave deserialized/hierarchy context unproven. Either outcome remains synthetic and cannot certify recovery/gameplay/deletion.",
        "rejectionRule": "No epsilon, value normalization, extra setters, native retry or changes to frozen/archive/failure evidence."},
    "preserve": "All authoritative held originals, full raw archive/facts, failed raw-only reopen, frozen V4, native completion/receiver verdict and earlier failures remain untouched.",
    "evidence": evidence, "frozenPinListSHA256": sha((HERE / "file-pins.json").read_bytes()),
    "reviewScriptSHA256": sha(Path(__file__).read_bytes())}
markdown = """# Native V4 fejlede sikkert ved den første setter

**S19 forbliver afventende; V4-opskriften består ikke.** Den faktiske Studio-rapport fra 08:18:37Z afviser den første testejede `Bone.CFrame` setter-verifikation. Den rå historiske recovery-port forbliver også fejlet. Dette er ingen godkendelse til native packagefjernelse.

Reviewet følger SHA-kæden fra de frosne Lua-kilder gennem den faktiske MCP-response, Roots uændrede completion-bytes og receiverens `recipePassed=false`. Baseline bestod med 213 friske Source/editor-/identity-/metadata-pins, 52 ServerStorage-rødder og 416284 live descendants. Frosne kilder og fem historiske inddata er stadig byte-eksakte.

Setter-kaldet returnerede, hvorefter den kombinerede assertion `copy.CFrame == wanted AND after12 == spec12` fejlede. Der var ét forsøg og én returneret assignment; det betyder ikke, at værdien blev gendannet eksakt. Den native completion registrerer hverken after-komponenterne eller de to predicates hver for sig. Vi kan derfor ikke udpege komponent/delta eller fastslå normalisering som årsag. Første target kan udledes fra den pinnede arrays rækkefølge som `TEMP_PipeEntityValidation.PipeEntity_LocalPreview.RootPart.Root.Hips.LeftUpperLeg`; receiptet registrerede ikke selv target. De gamle DS R21-forskelle må ikke præsenteres som dette forsøgs after-setter-tal.

Alle 23 skabte/adopterede testrødder blev destrueret, nul var tilbage, og egen lease blev frigivet. De afsluttende guards bekræfter uændret original native archive samt alle 213 Source-pins; Source-/original Parent-/mode-writes er nul. Der er ingen autoritativ regression observeret af disse guards og ingen original rollback at anvende. Der blev ikke gennemført fire setters, fuld efter-supplement-verifikation, anden genåbning eller native transfer. De 3.167.424 checks og testens varighed er ikke en gameplay-/performance- eller recovery-pass.

Bevar alle held-originaler, raw archive/facts, det tidligere raw-only FAIL, frosset V4, denne faktiske fejl og receiverens FAIL. Ændr ikke tolerance, baseline eller setterlisten; prøv ikke native V4 igen. Fortsæt uafhængige afklarede oprydningskandidater. S04's fem pakker har fortsat deres egne manglende gameplay-/multiplayer-/streaming-porte.

En mulig senere årsagsdiagnostik er kun et forslag: højst én ny, uparentet Bone, fire pinnede wanted-værdier, alle 12 expected/wanted/after-tal med `%.17g`, separate equality-predicates og præcise differing indices. Den må hverken bruge DS, originale Bones, levende parents eller originale setters og skal have friske originale guards samt cleanup på success/throw. En fejl dér kan afgrænse setter-stien; et match beviser ikke den deserialiserede hierarkis recovery. Ingen diagnostikkode er oprettet eller eksekveret her.

Maskinlæsbar kontrol, præcise inddatahashes og native evidence findes i `NATIVE_FAILURE_REVIEW.json`. Reviewet foretog nul Studio-kald og ændrede ingen originaler, frosne kilder, tidligere kvitteringer, manifest, index eller commits.
"""
with (HERE / "NATIVE_FAILURE_REVIEW.md").open("xb") as stream:
    stream.write(markdown.encode())
result["reviewMarkdownSHA256"] = sha(markdown.encode())
with (HERE / "NATIVE_FAILURE_REVIEW.json").open("xb") as stream:
    stream.write((json.dumps(result, indent=2) + "\n").encode())
print(json.dumps({"reviewPassed": True, "checks": checks, "recipePassed": False,
    "nativeCallsByReviewer": 0, "nativeEvidenceFiles": len(evidence)}))
