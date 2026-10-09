"""LE-32 unused write-only state proposal, actual targeting/stun/Stop offline.

Private unrelated perception/nav/capture systems are explicit boundaries.
Writes artifacts only; no native/runtime/manifest changes. Retains actual reason,
stunCooldownUntil, ThinkSeconds accumulator and all gameplay/diagnostic fields.
"""
import argparse
import difflib
import hashlib
import json
from pathlib import Path
import re
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
FILE = "ServerScriptService/Level 4 Systems/Level 4 Usher Controller.ModuleScript.lua"
SHA = lambda value: hashlib.sha256(value).hexdigest()
EDITS = [
    ("local target, targetReason = nil, nil", "local target = nil"),
    ("local nextHopAt, nextThinkAt, nextReplanAt = 0, 0, 0", "local nextHopAt, nextReplanAt = 0, 0"),
    ("local beamTime, stunUntil, stunCooldownUntil = 0, 0, 0", "local beamTime, stunCooldownUntil = 0, 0"),
    ("\ttargetReason = reason\n", ""),
    ("beamTime, stunUntil, stunCooldownUntil, nextHopAt = 0, 0, 0, 0", "beamTime, stunCooldownUntil, nextHopAt = 0, 0, 0"),
]


def section(body, start, stop):
    begin = body.index(start)
    return body[begin:body.index(stop, begin)]


def port(host, source, name):
    parts = {
        "__STATE__": section(source, "local session = 0", "local function now()"),
        "__SETSTATE__": section(source, "local function setState(name)", "-- ---------------------------------------------------------------- nav graph"),
        "__BEAMERS__": section(source, "local function setBeamers(list)", "-- ---------------------------------------------------------------- targeting"),
        "__CHOOSE__": section(source, "local function chooseTarget()", "-- ---------------------------------------------------------------- think + move"),
        "__THINK__": section(source, "local function think(elapsed)", "local function step(dt)"),
        "__STOP__": section(source, "function Usher.Stop()", "return Usher"),
    }
    result = host.replace("local function usherPort(e)", f"local function {name}(e)", 1)
    for key, value in parts.items():
        assert result.count(key) == 1
        result = result.replace(key, value)
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--luau", required=True)
    parser.add_argument("--compiler", required=True)
    parser.add_argument("--verify-installed", action="store_true")
    args = parser.parse_args()
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_raw = manifest_path.read_bytes()
    entry = next(item for item in json.loads(manifest_raw)["items"] if item["file"] == FILE)
    current_raw = (ROOT / FILE).read_bytes()
    current = current_raw.replace(b"\r\n", b"\n").decode()
    assert SHA(current.encode()) == entry["sha256"] and entry["sourceEditorMatches"] is True and entry["status"] == "synced"
    output = Path(__file__).with_name("usher-locals"); output.mkdir(exist_ok=True)
    preserved = {}
    before = current
    if args.verify_installed:
        proposal = output / "candidate-manifest.json"
        preserved[proposal] = proposal.read_bytes()
        saved = json.loads(preserved[proposal])
        assert saved["passed"] is True and saved["file"] == FILE
        for key in ("beforeFile", "candidateFile"):
            path = ROOT / saved[key]; preserved[path] = path.read_bytes()
        before = preserved[ROOT / saved["beforeFile"]].decode()
        assert SHA(before.encode()) == saved["beforeSHA256Lf"]
        assert current == preserved[ROOT / saved["candidateFile"]].decode() and SHA(current.encode()) == saved["candidateSHA256Lf"]
        for key in ("studioPath", "className", "properties", "attributes"):
            assert entry.get(key) == saved.get(key)
    assert len(re.findall(r"\btargetReason\b", before)) == 2
    assert len(re.findall(r"\bnextThinkAt\b", before)) == 1
    assert len(re.findall(r"\bstunUntil\b", before)) == 2
    candidate = before
    for old, new in EDITS:
        assert candidate.count(old) == 1
        candidate = candidate.replace(old, new, 1)
    if args.verify_installed:
        assert candidate == current
    base = Path(__file__).with_name("local-helpers-host.luau").read_text(encoding="utf-8")
    base += Path(__file__).with_name("additional-locals-host.luau").read_text(encoding="utf-8")
    fixture = Path(__file__).with_name("usher-locals-host.luau").read_text(encoding="utf-8")
    result = {"finding": "LE-32", "file": FILE, "status": "installed scoped candidates verified" if args.verify_installed else "proposal only; root native/CAS review required",
        "productionWrites": 0, "studioCalls": 0, "boundary": "offline actual chooseTarget/think/setState/setBeamers/Stop; unrelated private perception/nav/capture bodies are controlled boundaries", "compile": [], "tests": []}
    with tempfile.TemporaryDirectory(prefix="usher-locals-") as directory:
        probe = Path(directory) / "gate.luau"
        for label, body in (("before", before), ("candidate", candidate)):
            for optimization in (0, 1):
                probe.write_text(body, encoding="utf-8", newline="\n")
                compiled = subprocess.run([args.compiler, "--binary", "-g0", f"-O{optimization}", str(probe)], capture_output=True, timeout=30)
                assert compiled.returncode == 0, compiled.stderr.decode(errors="replace")
                result["compile"].append({"version": label, "optimization": optimization, "success": True, "bytecodeBytes": len(compiled.stdout), "bytecodeSHA256": SHA(compiled.stdout)})
        # Each port includes own fixture wrapper; duplicate definition has same semantics.
        source = base + port(fixture, before, "beforePort") + port(fixture, candidate, "candidatePort")
        source += '\ncheck(stable(usherFixture(beforePort))==stable(usherFixture(candidatePort)),"same targeting/stun/cooldown/reset diagnostics and event traces")\nprint("USHER PASS assertions="..checks)\n'
        probe.write_text(source, encoding="utf-8", newline="\n")
        gate = subprocess.run([args.luau, str(probe)], capture_output=True, text=True, timeout=30)
        assert gate.returncode == 0, gate.stdout + gate.stderr
        result["tests"].append({"name": "same actual targeting/stun/Stop contract", "passed": True, "assertions": int(re.search(r"assertions=(\d+)", gate.stdout)[1]), "output": gate.stdout.strip()})
        mutants = (("active target reason lost", candidate.replace('reason == "sight" or reason == "holder" or finale', 'false', 1), "reason still controls target mode holder"),
            ("active stun cooldown removed", candidate.replace('stunCooldownUntil = t + C.StunCooldownSeconds', 'stunCooldownUntil = 0', 1), "held stun keeps existing cooldown"))
        for label, body, expected in mutants:
            assert body != candidate
            probe.write_text(base + port(fixture, body, "mutant") + "\nusherFixture(mutant)\n", encoding="utf-8", newline="\n")
            mutant = subprocess.run([args.luau, str(probe)], capture_output=True, text=True, timeout=30)
            assert mutant.returncode != 0 and expected in mutant.stderr, mutant.stdout + mutant.stderr
            result["tests"].append({"name": label, "negativeControlRejected": True, "expectedFailure": expected})
    for key in ("studioPath", "className", "properties", "attributes"):
        result[key] = entry.get(key)
    result.update({"beforeSHA256Lf": SHA(before.encode()), "candidateSHA256Lf": SHA(candidate.encode()), "beforeBytesLf": len(before.encode()), "candidateBytesLf": len(candidate.encode()),
        "beforeFile": (output / "Usher.before.luau").relative_to(ROOT).as_posix(), "candidateFile": (output / "Usher.candidate.luau").relative_to(ROOT).as_posix(),
        "diff": "".join(difflib.unified_diff(before.splitlines(keepends=True), candidate.splitlines(keepends=True), fromfile=FILE, tofile=FILE, n=2)), "passed": True})
    assert manifest_path.read_bytes() == manifest_raw and (ROOT / FILE).read_bytes() == current_raw
    assert all(path.read_bytes() == data for path, data in preserved.items())
    if args.verify_installed:
        result["immutableProposalEvidenceUnchanged"] = True
    else:
        (output / "Usher.before.luau").write_text(before, encoding="utf-8", newline="\n")
        (output / "Usher.candidate.luau").write_text(candidate, encoding="utf-8", newline="\n")
    receipt = output / ("installed-contract-check.json" if args.verify_installed else "candidate-manifest.json")
    receipt.write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print(json.dumps(result["tests"], indent=2))
    print("4 full-source compile gates; canonical/manifest/Studio unchanged.")


if __name__ == "__main__":
    main()
