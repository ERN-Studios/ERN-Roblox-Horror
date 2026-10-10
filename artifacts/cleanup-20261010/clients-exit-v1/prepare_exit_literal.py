"""Prepare one unread literal deletion and whole-source contract; no Studio writes.

All outputs are fresh, owned artifacts. Existing production, manifest, index,
checkpoints, source packs, and historical test evidence are never rewritten.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import re
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[3]
HERE = Path(__file__).resolve().parent
TARGET = "StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua"
BEFORE = "13b6fdf722449d063204c7e4ee5275d06b7056c78be860a829abc4cee905bae3"
AFTER = "bd1cdb46003ae1dd4f151f1c1a0cc7c2ca85ed4add9dd9fe18a27bd765e20752"
BLOCK = 'local HINT_HEIGHT = 36      -- two wrapped lines of the explanation band\n'
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
COMPILER = LUAU.with_name("luau-compile.exe")
SHA = lambda raw: hashlib.sha256(raw).hexdigest()
LF = lambda raw: raw.replace(b"\r\n", b"\n")


def module(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    loaded = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(loaded)
    return loaded


def save(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        stream.write(raw)


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def proposal():
    before = LF((ROOT / TARGET).read_bytes())
    assert SHA(before) == BEFORE, "Fresh target differs; re-read Studio, no silent historical fallback"
    source = before.decode()
    assert source.count(BLOCK) == 1 and len(re.findall(r"\bHINT_HEIGHT\b", source)) == 1
    after = source.replace(BLOCK, "", 1).encode()
    assert SHA(after) == AFTER and len(before) - len(after) == 73
    manifest = json.loads((ROOT / "studio-sync-manifest.json").read_bytes())
    target = [row for row in manifest["items"] if row.get("file") == TARGET]
    assert len(target) == 1 and target[0]["sha256"] == BEFORE and target[0]["bytes"] == len(before)
    assert target[0]["className"] == "LocalScript"
    assert target[0]["properties"] == {"Disabled": False, "LinkedSource": "", "Archivable": True,
        "RunContext": "Enum.RunContext.Legacy", "Enabled": True}
    assert target[0].get("attributes", []) == []
    return before, after, target[0], manifest


def compile_sources(before, after):
    verifier = module("exit_canonical_v14", ROOT / "artifacts/cleanup-20261009/verify_C08.py")
    ports = []
    padded = before.replace(BLOCK.encode(), b"\n", 1)
    with tempfile.TemporaryDirectory(prefix="mongotv-exit-literal-source-") as folder:
        file = Path(folder) / "same-input.luau"
        for optimization in (0, 1):
            binaries, dumps, canonical, counts = {}, {}, {}, {}
            for label, body in (("before", before), ("candidate", after), ("linePreserved", padded)):
                file.write_bytes(body)
                flags = ["-g0", f"-O{optimization}", str(file)]
                run = subprocess.run([str(COMPILER), "--binary", *flags], capture_output=True, timeout=20)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                binaries[label] = run.stdout
                canonical[label], metadata = verifier.canonical(run.stdout)
                counts[label] = len(metadata)
                run = subprocess.run([str(COMPILER), "--text", "--dump-constants", *flags], capture_output=True, timeout=20)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                dumps[label] = run.stdout
            if optimization == 1:
                assert canonical["before"] == canonical["candidate"]
                assert dumps["before"] == dumps["candidate"]
                assert binaries["before"] == binaries["linePreserved"]
            ports.append({"pass": True, "optimization": optimization, "debug": 0,
                "functions": counts, "canonicalIdentical": canonical["before"] == canonical["candidate"],
                "textWithConstantsIdentical": dumps["before"] == dumps["candidate"],
                "linePreservedBinaryIdentical": binaries["before"] == binaries["linePreserved"],
                "beforeBinarySHA256": SHA(binaries["before"]), "candidateBinarySHA256": SHA(binaries["candidate"]),
                "beforeCanonicalSHA256": SHA(canonical["before"]), "candidateCanonicalSHA256": SHA(canonical["candidate"])})
    return ports


def contract_source(exit_source, hud, contracts):
    sources = {name: LF(path.read_bytes()).decode() for name, path in hud.SOURCES.items()}
    sources["ExitClient"] = exit_source.decode()
    trees = {name: json.loads((hud.DUMPS / ("framewisp-dump." + name + ".json")).read_bytes())["root"]
             for name in ("HUD_PC", "HUD_Touch")}
    # All production bodies are byte-for-byte in fresh function factories. No
    # loadstring permission, cloned script, or shared module cache is required.
    inject = "local SOURCES = {" + ",".join(name + "=true" for name in sources) + "}\n"
    inject += "local FACTORIES = {\n" + ",\n".join(
        name + "=function() return function()\n" + body + "\nend end" for name, body in sources.items()) + "\n}\n"
    inject += "local TREES = " + hud.lua(trees) + "\n"
    harness = LF(hud.HARNESS.read_bytes()).decode()
    assert harness.count("--@@INJECT@@") == 1
    harness = harness.replace("--@@INJECT@@", inject, 1)
    old_load = 'local fn = assert(loadstring(SOURCES[name], "=" .. name))'
    assert harness.count(old_load) == 1
    harness = harness.replace(old_load, 'local fn = assert(FACTORIES[name], "known factory")()', 1)
    assert harness.count("local game = {GetService") == 1
    harness = harness.replace("local game = {GetService", "ctx.Services=services\n\tlocal game = {GetService", 1)
    old_fallback = "}, {__index = _G})"
    assert harness.count(old_fallback) == 1
    harness = harness.replace(old_fallback, "}, {__index = getfenv()})", 1)
    assert not re.search(r"\bloadstring\s*\(", harness)
    tests = contracts.TESTS
    stop = '\ndo\n local ctx=boot(false);ctx.Workspace:SetAttribute("RoundStartedAt",-3661)'
    assert tests.count(stop) == 1
    tests = tests[:tests.index(stop)]
    # Exact existing whole Exit checks, independent of the unrelated footage,
    # interaction-prompt and hiding test bodies that follow in the shared suite.
    tail = r'''
-- Early missing-import path: the source warns, destroys its owned GUI and
-- returns before binding hold/input callbacks. Controlled assets boundary.
do
 local ctx=boot(false)
 ctx.Templates:FindFirstChild("HUD_PC"):Destroy()
 ctx.Templates:FindFirstChild("HUD_Touch"):Destroy()
 ctx:Require("ExitClient")
 check(ctx.PlayerGui:FindFirstChild("RoundExitGui")==nil,"missing imports destroy the partial owned exit GUI")
 check(ctx:Warned("Round Exit Client: missing imported HUD templates")==1,"missing imports warn once")
 ctx:Key("L");ctx:Step(2)
 check(#ctx.Requests==0,"missing imports install no hold flow")
end
return {pass=true,checks=checks,scope="Whole actual Round Exit source, real source dependencies and imported fixture trees; controlled engine/player/input/transport/timer/UIDevice boundaries. Not native assets, gameplay, hardware, multiplayer, streaming or teleport certification."}
'''
    return "return function()\n" + harness + "\n" + tests + tail + "\nend\n", sources


def run_payload(payload, label):
    compiles = []
    with tempfile.TemporaryDirectory(prefix="mongotv-exit-literal-port-") as folder:
        file = Path(folder) / "contract.module.luau"
        file.write_bytes(payload.encode())
        for optimization in (0, 1):
            run = subprocess.run([str(COMPILER), "--binary", f"-O{optimization}", str(file)], capture_output=True, timeout=20)
            assert run.returncode == 0, run.stderr.decode(errors="replace")
            compiles.append({"pass": True, "optimization": optimization})
        runner = Path(folder) / "runner.luau"
        runner.write_text('local build=function()\n'+payload+'\nend\nlocal run=build()\nlocal a=run()\nassert(a.pass)\nlocal b=run()\nassert(b.pass and a.checks==b.checks)\nprint("EXIT_CHECKS="..a.checks.." REENTRY="..b.checks)\n', encoding="utf8")
        executed = subprocess.run([str(LUAU), str(runner)], capture_output=True, text=True, timeout=30)
        if label in ("before", "candidate"):
            assert executed.returncode == 0, executed.stdout + executed.stderr
            matched = re.search(r"EXIT_CHECKS=(\d+) REENTRY=(\d+)", executed.stdout)
            assert matched
            return {"phase": label, "pass": True, "checks": int(matched[1]), "reentryChecks": int(matched[2]),
                    "compile": compiles, "payloadSHA256": SHA(payload.encode())}
        assert executed.returncode != 0, "Semantic negative unexpectedly passed: " + label
        expected = "no early hold at" if label == "timingNegative" else "card cannot duplicate held request"
        assert expected in executed.stdout + executed.stderr, executed.stdout + executed.stderr
        return {"phase": label, "pass": True, "expectedFailure": expected, "compile": compiles,
                "payloadSHA256": SHA(payload.encode()), "scope": "Expected semantic control rejected; no production mutation"}


def prepare():
    before, after, target, manifest = proposal()
    destination = HERE / "proposal-v1"
    assert not destination.exists(), "Preserve immutable proposal"
    sys.path.insert(0, str(ROOT / "tools/tests"))
    import test_round_hud as hud
    import test_hud_b6_b7 as contracts
    source_ports = compile_sources(before, after)
    patches = {
        "before": before,
        "candidate": after,
        "timingNegative": after.replace(b"local HOLD_SECONDS = 1.5", b"local HOLD_SECONDS = 0.5", 1),
        "requestNegative": after.replace(b"\tif requestPending then return end\n", b"", 1),
    }
    assert patches["timingNegative"] != after and patches["requestNegative"] != after
    payloads, ports = {}, []
    for label, body in patches.items():
        payload, sources = contract_source(body, hud, contracts)
        payloads[label] = payload
        ports.append(run_payload(payload, label))
    assert ports[0]["checks"] == ports[1]["checks"] and ports[0]["reentryChecks"] == ports[1]["reentryChecks"]
    files = list(hud.SOURCES.values()) + [ROOT/TARGET, hud.HARNESS, Path(contracts.__file__), Path(hud.__file__),
        ROOT/"ReplicatedStorage/UIDevice.ModuleScript.lua", ROOT/"StarterPlayer/StarterPlayerScripts/SpectateController.LocalScript.lua",
        ROOT/"ServerScriptService/GameManager.Script.lua"]
    files += [hud.DUMPS/("framewisp-dump."+name+".json") for name in ("HUD_PC","HUD_Touch")]
    closure = []
    by_file = {row.get("file"): row for row in manifest["items"]}
    for file in files:
        relative = file.relative_to(ROOT).as_posix();raw=file.read_bytes()
        row = {"file": relative, "rawBytes": len(raw), "rawSHA256": SHA(raw), "lfSHA256": SHA(LF(raw))}
        if relative in by_file:
            native = by_file[relative]
            assert native["sha256"] == SHA(LF(raw)), "Fresh dependency mirror/manifest mismatch: " + relative
            row["manifest"] = native
        closure.append(row)
    proof = {"schema": "mongotv-exit-unread-literal-proposal-v1", "pass": True, "candidate": "C04/B12",
        "status": "offline gates passed; fresh parent native before/candidate/installed and scoped CAS pending",
        "file": TARGET, "beforeSHA256": BEFORE, "candidateSHA256": AFTER, "beforeBytes": len(before),
        "candidateBytes": len(after), "bytesRemoved": 73, "removedLine": 55, "targetManifest": target,
        "nativeScriptCountObserved": manifest["counts"]["scripts"], "sourceCompiler": source_ports,
        "contractPorts": ports, "closure": closure, "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
        "scope": "One unread private number literal only; no runtime feature, constructor, callback, require or protocol removed",
        "limits": "Actual full production sources run with fake engine/player/input/transport/timer/UIDevice and historical imported asset fixture boundaries; not a native asset/gameplay/multiplayer/streaming/performance certificate."}
    save(destination/".gitattributes", b"* -text\n")
    save(destination/"before.source.luau", before);save(destination/"candidate.source.luau", after)
    for label, payload in payloads.items():save(destination/(label+".module.luau"),payload.encode())
    save(destination/"proposal.json",encoded(proof))
    print(json.dumps({"pass": True, "removedBytes":73,"checksPerVersion":ports[0]["checks"],"reentryPerVersion":ports[0]["reentryChecks"],"semanticNegativeControls":2,"nativeCalls":0,"productionWrites":0}),flush=True)


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.parse_args()
    prepare()
