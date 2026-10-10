"""Pin the V2 transport-only delta and preserve the frozen V1 baseline."""
from pathlib import Path
import hashlib
import json

HERE=Path(__file__).resolve().parent
ROOT=HERE.parents[3]
OLD=HERE.parent/"installer-v1"
sha=lambda raw:hashlib.sha256(raw).hexdigest()
assert sha((OLD/"frozen-pins-v1.json").read_bytes())=="474551f2f33654b5589aa1c405cc93eed5e8b350b888083dfd73f9fe3aed1890"
for row in json.loads((OLD/"frozen-pins-v1.json").read_bytes())["files"]:
    raw=(ROOT/row["file"]).read_bytes()
    assert len(raw)==row["rawBytes"] and sha(raw)==row["rawSHA256"], "Frozen V1 changed"
assert (HERE/"exit_literal_source_cas.luau").read_bytes()==(OLD/"exit_literal_source_cas.luau").read_bytes(),"Native template must remain identical"
codes=["apply_exit_literal_cleanup.py","exit_literal_source_cas.luau","test_apply_exit_literal_cleanup.py",
       "test_exit_native_cas_guards.py","test_exit_parser_faults.py","verify_exit_install_proposal.py","REVIEW.md","freeze_installer.py"]
evidence=["offline-wrapper-tests-v2.json","native-guard-tests-v1.json","parser-fault-tests-v1.json","offline-refresh-v2/result.json",
          "offline-refresh-v2/offline-helper/result.json","offline-refresh-v2/offline-helper/neighbors.json"]
wrapper=json.loads((HERE/"offline-wrapper-tests-v2.json").read_bytes())
app_sha=sha((HERE/"apply_exit_literal_cleanup.py").read_bytes())
template_sha=sha((HERE/"exit_literal_source_cas.luau").read_text(encoding="utf8").encode())
assert wrapper["pass"] is True and len(wrapper["cases"])==54 and wrapper["checks"]==500
assert wrapper["wrapperSHA256"]==app_sha and wrapper["templateSHA256"]==template_sha
for name,cases,checks in (("native-guard-tests-v1.json",15,75),("parser-fault-tests-v1.json",31,317)):
    proof=json.loads((HERE/name).read_bytes())
    assert proof["pass"] is True and proof["cases"]==cases and proof["checks"]==checks and proof["templateSHA256"]==template_sha
actual=json.loads((HERE/"offline-refresh-v2/result.json").read_bytes())
assert actual["pass"] is True and actual["wrapperSHA256"]==app_sha and actual["templateSHA256"]==template_sha and len(actual["templateCompiles"])==14
paths=[HERE/name for name in codes+evidence]+[HERE.parent/"prepare_installer_v2.py",ROOT/"tools/sync_from_studio.py",OLD/"frozen-pins-v1.json"]
pins=[]
for path in paths:
    raw=path.read_bytes();pins.append({"file":path.relative_to(ROOT).as_posix(),"rawBytes":len(raw),"rawSHA256":sha(raw)})
proof={"schema":"mongotv-exit-literal-installer-frozen-pins-v2","pass":True,"status":"frozen transport-only candidate; independent delta peer and Root native parser/CAS/export/after gates pending",
       "nativeTemplateIdenticalToV1":True,"v1FrozenFilesPreserved":True,"delta":"single pending-outcome _request path for apply/rollback/compile; no further calls/recovery while transport outcome is unknown",
       "files":pins,"offlineGateSummary":{"wrapperCases":54,"wrapperChecks":500,"newTransportRecoveryCases":8,"actualNativeGuardCases":15,"actualNativeGuardChecks":75,
          "actualParserFaultCases":31,"actualParserFaultChecks":317,"templateCompiles":14,"pairedChecksPerVersion":50,"reentryChecksPerVersion":50,"neighborChecksPerVersion":92,"semanticMutants":2,"canonicalO1Equivalent":True},
       "nativeCalls":0,"productionWrites":0,"manifestWrites":0,
       "limits":"Actual wrapper/files/CAS rollback with controlled MCP/native transport outcomes. All native execution and final parity remain Root-owned; no gameplay/MP/streaming/teleport/asset/performance claims."}
with (HERE/"frozen-pins-v1.json").open("xb") as stream:stream.write((json.dumps(proof,indent=2,ensure_ascii=False)+"\n").encode())
print(json.dumps({"pass":True,"pins":len(pins),"codes":[row for row in pins if Path(row["file"]).name in codes[:6]],"frozenPinsSHA256":sha((HERE/"frozen-pins-v1.json").read_bytes())}))
