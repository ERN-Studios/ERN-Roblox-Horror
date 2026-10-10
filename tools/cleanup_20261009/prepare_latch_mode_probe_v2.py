"""Root-only hardened LE34 native replay. Default is offline preparation only.

Preserves the exact executed v1 tools/inputs/receipts and the 47-check contracts.
Only --execute can call Studio; never installs production Source or changes mode.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
ART = ROOT / "artifacts/cleanup-20261009/pending-locals-native-v1"
DEST = ART / "latch-only-v2"
spec = importlib.util.spec_from_file_location("immutable_v1_probe", Path(__file__).with_name("prepare_latch_mode_probe.py"))
v1 = importlib.util.module_from_spec(spec)
spec.loader.exec_module(v1)
sha = v1.sha


def ownership_fixture(template):
    # Execute the actual claim/release/guard code, not an imitation of its checks.
    lease = template[template.index("local token,ownedConnections="):template.index("local probes,created,destroyed=")]
    assert lease.endswith("claimLease()\n")
    lease = lease[:-len("claimLease()\n")]
    guard = template[template.index("local function guard(fullCensus)"):template.index("local function stage(name,body)")]
    prefix = '''local checks=0
local function check(ok,why) checks+=1;assert(ok,why) end
local function fresh()
 local shared={} local KEY="test" local allowed=true
 local function mode()assert(allowed,"mode changed")end
 local originalList,originalMap={},{}
'''
    suffix = '''
 return {shared=shared,key=KEY,state=state,token=token,connections=ownedConnections,
 claim=claimLease,release=releaseLease,guard=guard,owned=ownedLease,
 setMode=function(v)allowed=v end}
end
local a=fresh();a.claim();a.guard(false)
check(a.owned(),"normal lease owns exact state/token/connections")
check(a.release() and a.shared[a.key]==nil,"normal release clears only owned key")
local b=fresh();local foreign={token={},connections={},phase="foreign",report={keep=true}}
b.shared[b.key]=foreign;local ok=pcall(b.claim)
check(not ok,"post-census foreign lease rejects claim")
check(b.shared[b.key]==foreign and foreign.report.keep,"foreign preclaim state preserved")
for _,kind in {"token","connections","nonempty","phase","shared"} do
 local c=fresh();c.claim();local replacement={token={},connections={},phase="other",report={keep=true}}
 if kind=="token" then c.state.token={} elseif kind=="connections" then c.state.connections={}
 elseif kind=="nonempty" then c.connections.foreign=true elseif kind=="phase" then c.state.phase="foreign"
 else c.shared[c.key]=replacement end
 local saved=c.shared[c.key];local token=saved.token;local connections=saved.connections;local phase=saved.phase
 check(not pcall(function()c.guard(false)end),kind.." exact guard rejects")
 check(not c.release(),kind.." release refuses foreign ownership")
 check(c.shared[c.key]==saved and saved.token==token and saved.connections==connections and saved.phase==phase,
  kind.." foreign metadata preserved")
end
local d=fresh();d.setMode(false)
check(not pcall(d.claim) and d.shared[d.key]==nil,"mode guard rejects before claim")
print("OWNERSHIP_CHECKS="..checks)
'''
    return prefix + lease + guard + suffix


def prepare():
    assert not DEST.exists(), "Immutable v2 proposal already exists"
    before = (ROOT / v1.PUZZLE).read_bytes()
    manifest = (ROOT / "studio-sync-manifest.json").read_bytes()
    old = json.loads((ART / "latch-only/proposal.json").read_bytes())
    assert sha(v1.lf(before)) == old["beforeSHA256"]
    assert json.loads(manifest)["counts"]["scripts"] == old["nativeScriptCount"] == 212
    template = Path(__file__).with_name("latch_mode_probe_v2.luau").read_text(encoding="utf8")
    payloads = {}
    for name, expected in old["payloadHashes"].items():
        raw = (ART / "latch-only" / (name + ".module.luau")).read_bytes()
        assert sha(raw) == expected
        payloads[name] = raw.decode()
    expected = {"nativeScriptCount": old["nativeScriptCount"], "contractChecks": old["checksPerVersion"], "originals": old["originals"]}
    codes = {}
    for mode in ("before", "installed"):
        values = json.loads(json.dumps(expected))
        if mode == "installed": values["originals"][0]["sourceSHA256"] = old["candidateSHA256"]
        code = template.replace("__EXPECTED__", v1.lua_literal(json.dumps(values, ensure_ascii=False)))
        code = code.replace("__PAYLOADS__", v1.lua_literal(json.dumps(payloads, ensure_ascii=False))).replace("__INSTALLED__", str(mode == "installed").lower())
        assert "__EXPECTED__" not in code and "__PAYLOADS__" not in code
        codes[mode] = code
    fixture = ownership_fixture(template)
    compiles = []
    with tempfile.TemporaryDirectory(prefix="mongotv-latch-v2-") as directory:
        temp = Path(directory)
        for name, body in {**codes, "ownership": fixture}.items():
            path = temp / (name + ".luau");path.write_bytes(body.encode())
            for optimization in ("-O0", "-O1"):
                run = subprocess.run([str(v1.COMPILER), "--binary", optimization, str(path)], capture_output=True, timeout=15)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compiles.append({"input": name, "optimization": optimization, "sourceSHA256": sha(body.encode()), "pass": True})
        run = subprocess.run([str(v1.LUAU), str(temp / "ownership.luau")], capture_output=True, text=True, timeout=15)
        assert run.returncode == 0, run.stdout + run.stderr
        import re
        checks = int(re.search(r"OWNERSHIP_CHECKS=(\d+)", run.stdout)[1])
    assert (ROOT / v1.PUZZLE).read_bytes() == before and (ROOT / "studio-sync-manifest.json").read_bytes() == manifest
    for name, code in codes.items(): v1.save(DEST / ("native-" + name + ".luau"), code.encode())
    v1.save(DEST / "ownership-fixture.luau", fixture.encode())
    proof = {"schema": "mongotv-latch-mode-probe-v2", "pass": True, "checksPerVersion": 47, "pairedChecks": 94, "reentryChecks": 94,
             "ownershipCases": 8, "ownershipChecks": checks, "compileChecks": compiles, "payloadHashes": old["payloadHashes"],
             "nativeCodeHashes": {name: sha(code.encode()) for name, code in codes.items()}, "templateSHA256": sha(template.encode()),
             "beforeSHA256": old["beforeSHA256"], "candidateSHA256": old["candidateSHA256"], "nativeScriptCount": old["nativeScriptCount"],
             "v1ProposalSHA256": sha((ART / "latch-only/proposal.json").read_bytes()), "v1ExecutedNativeSHA256": old["nativeCodeHashes"]["before"],
             "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
             "status": "offline ownership controls pass; parent must run fresh native-before-v2 before installation"}
    v1.save(DEST / "proposal.json", v1.encoded(proof))
    print(json.dumps({"pass": True, "ownershipChecks": checks, "nativeCalls": 0, "nativeCodeHashes": proof["nativeCodeHashes"]}))


def execute(mode, receipt):
    assert receipt is not None and not receipt.exists(), "Require a new immutable receipt"
    proposal = json.loads((DEST / "proposal.json").read_bytes())
    code = (DEST / ("native-" + mode + ".luau")).read_bytes()
    assert sha(code) == proposal["nativeCodeHashes"][mode]
    assert sha(v1.lf((ROOT / v1.PUZZLE).read_bytes())) == proposal["beforeSHA256" if mode == "before" else "candidateSHA256"]
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
    client = StudioMcpClient(find_mcp_batch())
    result = None;error = None
    try:
        client.initialize();studio = select_studio(client, RELEASE_STUDIO_NAME, 15)
        assert studio["id"] == "1b603e69-7ae1-4572-b210-d5bf05c684ff"
        assert "Current Studio Mode: Edit" in client.call("get_studio_state", {"studio_id": studio["id"]})
        result = json.loads(client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Edit", "code": code.decode()}))
    except BaseException as primary: error = primary
    finally:
        try: client.close()
        except BaseException as cleanup:
            if error is None: error = cleanup
            else: error.add_note("MCP cleanup: " + str(cleanup))
        if result is None: result = {"pass": False}
        if error is not None: result.update({"pass": False, "transportError": str(error)})
        result["nativeInputSHA256"] = sha(code)
        v1.save(receipt, v1.encoded(result))
    print(json.dumps({key: result.get(key) for key in ("pass", "contractPassed", "originalsUnchanged", "probesCreated", "probesDestroyed", "remainingProbes", "error", "transportError")}))
    assert error is None and result.get("pass") is True, "Native gate failed; keep candidate pending"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--execute", choices=("before", "installed"));parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.execute: execute(args.execute, args.receipt)
    else: prepare()


if __name__ == "__main__": main()
