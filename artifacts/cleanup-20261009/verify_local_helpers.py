"""Prepare only LE-32 isStar / LE-34 lampShade proposals, never edit game files.

Run actual whole LightDirector and actual CD-player constructor block at offline
engine boundaries. Compare the same lifecycle/authoring graphs before/after;
reject semantic negative controls. This is not a native/client/physics test.
"""
import argparse
import difflib
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
SHA = lambda data: hashlib.sha256(data).hexdigest()
LIGHT = "ServerScriptService/Level 4 Systems/Level 4 Light Director.ModuleScript.lua"
LAMP = "ServerScriptService/Level 3 Systems/Level 3 Worn Party Visual Adapter.ModuleScript.lua"
OLD_STAR = '''local function isStar(part)
\tfor _, tag in ipairs(STAR_TAGS) do
\t\tif CollectionService:HasTag(part, tag) then return true end
\tend
\treturn false
end

'''
OLD_LAMP = 'local lampShade = devicePart("CD Player Task Lamp Shade", CFrame.new(0,7.16,1.48),'
NEW_LAMP = 'devicePart("CD Player Task Lamp Shade", CFrame.new(0,7.16,1.48),'


def lamp_block(body):
    start = body.index('    local function devicePart(name, relativeCF, size, color, material)')
    end = body.index('    taskLight.Parent = taskLamp', start)
    return body[start:end + len('    taskLight.Parent = taskLamp')]


def light_loader(name, body):
    return f'''local function {name}(e)
local game, script, workspace, task, Instance, require = e.game,e.script,e.workspace,e.task,e.Instance,e.require
{body}
end
'''


def lamp_loader(name, body):
    return f'''local function {name}(e,model,cf)
local Instance=e.Instance
local player, playerCF={{Model=model}},cf
{lamp_block(body)}
end
'''


def run_luau(binary, body, path):
    path.write_text(body, encoding="utf-8", newline="\n")
    return subprocess.run([binary, str(path)], capture_output=True, text=True, timeout=30)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", default=os.environ.get("LUAU_BIN") or shutil.which("luau"))
    parser.add_argument("--compiler", default=os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile"))
    parser.add_argument("--verify-installed", action="store_true", help="Rerun immutable proposal contracts against exact installed candidate; save separate receipt")
    args = parser.parse_args()
    assert args.luau and args.compiler, "Provide --luau and --compiler"
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_raw = manifest_path.read_bytes()
    manifest = json.loads(manifest_raw)
    assert manifest["placeId"] == 131311258779917 and manifest["universeId"] == 10559217407
    entries = {item["file"]: item for item in manifest["items"]}
    captured = {name: (ROOT / name).read_bytes() for name in (LIGHT, LAMP)}
    current = {name: raw.replace(b"\r\n", b"\n").decode("utf-8") for name, raw in captured.items()}
    artifact_dir = Path(__file__).with_name("local-helpers")
    artifact_dir.mkdir(exist_ok=True)
    baseline = dict(current)
    preserved = {}
    saved_candidate = {}
    if args.verify_installed:
        proposal_path = artifact_dir / "candidate-manifest.json"
        preserved[proposal_path] = proposal_path.read_bytes()
        proposal = json.loads(preserved[proposal_path])
        assert proposal["passed"] is True
        saved = {item["file"]: item for item in proposal["files"]}
        assert set(saved) == {LIGHT, LAMP}
        for name, item in saved.items():
            before_path, candidate_path = ROOT / item["beforeFile"], ROOT / item["candidateFile"]
            preserved[before_path], preserved[candidate_path] = before_path.read_bytes(), candidate_path.read_bytes()
            baseline[name], saved_candidate[name] = preserved[before_path].decode(), preserved[candidate_path].decode()
            assert SHA(baseline[name].encode()) == item["beforeSHA256Lf"]
            assert SHA(saved_candidate[name].encode()) == item["candidateSHA256Lf"]
            assert current[name] == saved_candidate[name], "Installed source is not exact saved candidate"
            for key in ("studioPath", "className", "properties", "attributes"):
                assert entries[name].get(key) == item.get(key), f"Installed metadata drift: {key}"
    for name in captured:
        assert entries[name]["status"] == "synced" and entries[name]["sourceEditorMatches"] is True
        assert SHA(current[name].encode()) == entries[name]["sha256"], "Fresh file/manifest mismatch"
    assert baseline[LIGHT].count(OLD_STAR) == 1
    assert len(re.findall(r"\bisStar\b", baseline[LIGHT])) == 1, "Private helper acquired a caller/capture"
    assert baseline[LAMP].count(OLD_LAMP) == 1
    assert len(re.findall(r"\blampShade\b", baseline[LAMP])) == 1, "Binding acquired a reader"
    candidate = {LIGHT: baseline[LIGHT].replace(OLD_STAR, "", 1), LAMP: baseline[LAMP].replace(OLD_LAMP, NEW_LAMP, 1)}
    if args.verify_installed:
        assert candidate == saved_candidate, "Proposal no longer matches exact scoped substitutions"
    assert candidate[LIGHT].count('"L4StarTwinkleC"') == baseline[LIGHT].count('"L4StarTwinkleC"') == 1
    assert candidate[LIGHT].count("local STAR_TAGS") == 1 and candidate[LIGHT].count("ipairs(STAR_TAGS)") == 1
    assert candidate[LAMP].count('devicePart("CD Player Task Lamp Shade"') == baseline[LAMP].count('devicePart("CD Player Task Lamp Shade"') == 1
    host = Path(__file__).with_name("local-helpers-host.luau").read_text(encoding="utf-8")
    result = {"status": "installed exact candidates verified; native receipts owned by root" if args.verify_installed else "proposal only; root native baseline/CAS review required", "productionWrites": 0,
        "studioCalls": 0, "scope": "pure private unused function; unused return binding with side-effectful call retained",
        "testBoundary": "offline actual-source engine-boundary contract; no native, physics, clients, streaming or installed kit claim",
        "files": [], "tests": []}
    with tempfile.TemporaryDirectory(prefix="local-helpers-") as directory:
        probe = Path(directory) / "gate.luau"
        for name, key, finding in ((LIGHT, "LightDirector", "LE-32"), (LAMP, "VisualAdapter", "LE-34")):
            compile_gates = []
            for version, body in (("before", baseline[name]), ("candidate", candidate[name])):
                for optimization in (0, 1):
                    probe.write_text(body, encoding="utf-8", newline="\n")
                    compiled = subprocess.run([args.compiler, "--binary", "-g0", f"-O{optimization}", str(probe)], capture_output=True, timeout=30)
                    assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
                    compile_gates.append({"version": version, "optimization": optimization, "success": True,
                        "bytecodeBytes": len(compiled.stdout), "bytecodeSHA256": SHA(compiled.stdout)})
            before_path = artifact_dir / f"{key}.before.luau"
            after_path = artifact_dir / f"{key}.candidate.luau"
            if not args.verify_installed:
                before_path.write_text(baseline[name], encoding="utf-8", newline="\n")
                after_path.write_text(candidate[name], encoding="utf-8", newline="\n")
            entry = entries[name]
            result["files"].append({"finding": finding, "file": name, "studioPath": entry["studioPath"],
                "className": entry["className"], "properties": entry.get("properties"), "attributes": entry.get("attributes"),
                "beforeSHA256Lf": SHA(baseline[name].encode()), "candidateSHA256Lf": SHA(candidate[name].encode()),
                "beforeBytesLf": len(baseline[name].encode()), "candidateBytesLf": len(candidate[name].encode()),
                "beforeFile": before_path.relative_to(ROOT).as_posix(), "candidateFile": after_path.relative_to(ROOT).as_posix(),
                "compile": compile_gates,
                "diff": "".join(difflib.unified_diff(baseline[name].splitlines(keepends=True), candidate[name].splitlines(keepends=True), fromfile=name, tofile=name, n=2))})
        source = host + light_loader("lightBefore", baseline[LIGHT]) + light_loader("lightAfter", candidate[LIGHT])
        source += lamp_loader("lampBefore", baseline[LAMP]) + lamp_loader("lampAfter", candidate[LAMP])
        source += '''
local lightOriginal,lightChanged=lightFixture(lightBefore),lightFixture(lightAfter)
check(stable(lightOriginal)==stable(lightChanged),"LightDirector same public API, module reads and lifecycle instance/event/attribute graph")
local lampOriginal,lampChanged=lampFixture(lampBefore,false),lampFixture(lampAfter,false)
check(stable(lampOriginal)==stable(lampChanged),"same authored CD display graph including lamp shade/light")
local lampErrorOriginal,lampErrorChanged=lampFixture(lampBefore,true),lampFixture(lampAfter,true)
check(stable(lampErrorOriginal)==stable(lampErrorChanged),"same constructor allocation-error behavior and partial graph")
print("CONTRACT PASS assertions="..checks)
print("LightLifecycleSHAInput="..stable(lightOriginal))
print("LampGraphSHAInput="..stable(lampOriginal))
print("LampErrorSHAInput="..stable(lampErrorOriginal))
'''
        gate = run_luau(args.luau, source, probe)
        assert gate.returncode == 0, gate.stdout + gate.stderr
        count = int(re.search(r"CONTRACT PASS assertions=(\d+)", gate.stdout).group(1))
        result["tests"].append({"name": "actual-source before/after contracts", "passed": True, "assertions": count,
            "traceSHA256": SHA(gate.stdout.encode()), "traceLines": len(gate.stdout.splitlines())})
        # Mutants change an active contract, rather than merely compare an edit to itself.
        bad_light = candidate[LIGHT].replace(', "L4StarTwinkleC"', '', 1)
        assert bad_light != candidate[LIGHT]
        bad_lamp = re.sub(r'    devicePart\("CD Player Task Lamp Shade"[^\n]*\n[^\n]*\n', '', candidate[LAMP], count=1)
        assert bad_lamp != candidate[LAMP]
        controls = (("active STAR_TAG_C omitted", light_loader("mutant", bad_light), "lightFixture(mutant)", "every active STAR_TAG is off"),
            ("side-effectful shade constructor omitted", lamp_loader("mutant", bad_lamp), "lampFixture(mutant,false)", "all nine display/support/lamp/shade parts remain"))
        for label, loader, call, reason in controls:
            mutant = run_luau(args.luau, host + loader + "\n" + call + "\n", probe)
            assert mutant.returncode != 0 and reason in mutant.stderr, mutant.stdout + mutant.stderr
            result["tests"].append({"name": label, "negativeControlRejected": True, "expectedFailure": reason})
    assert manifest_path.read_bytes() == manifest_raw, "Manifest changed during preparation; reconcile"
    assert all((ROOT / name).read_bytes() == value for name, value in captured.items()), "Canonical source changed; reconcile"
    assert all(path.read_bytes() == value for path, value in preserved.items()), "Immutable proposal evidence changed"
    result["passed"] = True
    result["currentManifestSHA256"] = SHA(manifest_raw)
    if args.verify_installed:
        result["immutableProposalEvidenceUnchanged"] = True
        result["immutableProposalEvidenceSHA256"] = {path.relative_to(ROOT).as_posix(): SHA(value) for path, value in preserved.items()}
    receipt = artifact_dir / ("installed-contract-check.json" if args.verify_installed else "candidate-manifest.json")
    receipt.write_text(json.dumps(result, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"PASS: {count} actual-source before/after contract assertions; 8 full-source compile gates; 2 semantic negative controls rejected.")
    print("Canonical sources, manifest and Studio unchanged; " + ("installed candidates match immutable evidence." if args.verify_installed else "proposals only."))
    print(receipt.relative_to(ROOT).as_posix())


if __name__ == "__main__":
    main()
