"""Pin only this prepared candidate and immutable local evidence; no Studio."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
sha=lambda body:hashlib.sha256(body).hexdigest()
code_names=["apply_exit_literal_cleanup.py","exit_literal_source_cas.luau","test_apply_exit_literal_cleanup.py",
            "test_exit_native_cas_guards.py","test_exit_parser_faults.py","verify_exit_install_proposal.py",
            "REVIEW.md","build_scoped_installer.py","build_offline_tests.py","development-failures-v1.json","freeze_installer.py"]
evidence=["offline-wrapper-tests-v3.json","native-guard-tests-v2.json","parser-fault-tests-v2.json","offline-refresh-v2/result.json",
          "offline-refresh-v2/offline-helper/result.json","offline-refresh-v2/offline-helper/neighbors.json"]
app_sha=sha((HERE/"apply_exit_literal_cleanup.py").read_bytes())
template_sha=sha((HERE/"exit_literal_source_cas.luau").read_text(encoding="utf8").encode())
wrapper=json.loads((HERE/"offline-wrapper-tests-v3.json").read_bytes())
assert wrapper["pass"] is True and len(wrapper["cases"])==46 and wrapper["checks"]==373
assert wrapper["wrapperSHA256"]==app_sha and wrapper["templateSHA256"]==template_sha
for name,cases,checks in (("native-guard-tests-v2.json",15,75),("parser-fault-tests-v2.json",31,317)):
    proof=json.loads((HERE/name).read_bytes())
    assert proof["pass"] is True and proof["cases"]==cases and proof["checks"]==checks and proof["templateSHA256"]==template_sha
actual=json.loads((HERE/"offline-refresh-v2/result.json").read_bytes())
assert actual["pass"] is True and actual["wrapperSHA256"]==app_sha and actual["templateSHA256"]==template_sha and len(actual["templateCompiles"])==14
files=[HERE/name for name in code_names+evidence]
files += [HERE.parent/"native-target-read-v1.json",HERE.parent/"proposal-v1/proposal.json",HERE.parent/"proposal-v1/before.source.luau",
          HERE.parent/"proposal-v1/candidate.source.luau",HERE.parent/"prepare_exit_literal.py",HERE.parent/"verify_exit_neighbors.py"]
pins=[]
for path in files:
    raw=path.read_bytes();pins.append({"file":path.relative_to(ROOT).as_posix(),"rawBytes":len(raw),"rawSHA256":sha(raw)})
result={"schema":"mongotv-exit-literal-installer-frozen-pins-v1","pass":True,"status":"frozen prepared candidate; independent peer/native parser/CAS/export/after parity pending",
        "scope":"Only one unused private pure number literal and its trailing comment; exact 73 LF bytes",
        "files":pins,"offlineGateSummary":{"wrapperCases":46,"wrapperChecks":373,"exclusiveFileCASCases":2,"exclusiveFileCASChecks":8,
            "actualTransformCases":5,"actualTransformChecks":8,"parserReceiptCases":9,"actualNativeGuardCases":15,"actualNativeGuardChecks":75,
            "actualParserFaultCases":31,"actualParserFaultChecks":317,"templateCompiles":14,"pairedChecksPerVersion":50,"reentryChecksPerVersion":50,
            "neighborChecksPerVersion":92,"semanticMutants":2,"canonicalO1Equivalent":True},
        "nativeCalls":0,"productionWrites":0,"manifestWrites":0,
        "limits":"Control boundaries explicitly documented; native execution and final parity remain Root-owned. No gameplay/multiplayer/streaming/teleport/asset/performance claims."}
with (HERE/"frozen-pins-v1.json").open("xb") as stream:stream.write((json.dumps(result,indent=2,ensure_ascii=False)+"\n").encode())
print(json.dumps({"pass":True,"pins":len(pins),"codes":[row for row in pins if Path(row["file"]).name in code_names[:6]],
                  "frozenPinsSHA256":sha((HERE/"frozen-pins-v1.json").read_bytes())}))
