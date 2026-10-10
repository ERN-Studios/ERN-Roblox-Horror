"""Prepare C06's exact client no-op cleanup and bind Root's fresh metadata.

No Studio calls, production or manifest writes. --bind-native writes a new
immutable code binding only after fresh manifest/source/identity validation.
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
ART = Path(__file__).resolve().parent
PROPOSAL = ART / "proposal-v1"
FILE = "StarterPlayer/StarterPlayerScripts/Level4PreviewPrompt.LocalScript.lua"
BEFORE = "161206ea81938d5a10408bc85f6c2b027c37015cc51378b3d721cbb8323c4436"
BLOCK = ('-- ZenMeister02 can see only the isolated Level 6 preview doorway.\n'
         'if Players.LocalPlayer.UserId == 11374988579 then\n'
         '\tPROMPTS.Level6DeveloperPreviewPrompt = nil\n'
         '\tPROMPTS.Level6DeveloperPreviewReturnPrompt = nil\n'
         'end\n')
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
COMPILER = LUAU.with_name("luau-compile.exe")
sha = lambda value: hashlib.sha256(value).hexdigest()
lf = lambda value: value.replace(b"\r\n", b"\n")


def encoded(value):
    return (json.dumps(value, indent=2, ensure_ascii=False) + "\n").encode()


def save(path, value):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as out:
        assert out.write(value) == len(value)
    assert path.read_bytes() == value


def lua_literal(value):
    level = "="
    while "]" + level + "]" in value:
        level += "="
    return "string.sub([" + level + "[_" + value + "]" + level + "],2)"


def load_canonical():
    path = ROOT / "artifacts/cleanup-20261009/verify_C08.py"
    spec = importlib.util.spec_from_file_location("existing_c08_parser", path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def prepare():
    assert not PROPOSAL.exists(), "Immutable proposal already exists; use a new version"
    raw = (ROOT / FILE).read_bytes()
    manifest_raw = (ROOT / "studio-sync-manifest.json").read_bytes()
    before = lf(raw)
    assert sha(before) == BEFORE, "Fresh current LF Source changed; re-review candidate"
    source = before.decode("utf8")
    assert source.count(BLOCK) == 1 and len(BLOCK.encode()) == 215
    literal = source[source.index("local PROMPTS = {"):source.index("-- Fail closed:")]
    assert "Level6DeveloperPreviewPrompt" not in literal and "Level6DeveloperPreviewReturnPrompt" not in literal
    assert source.count("PROMPTS =") == 1 and source.count("PROMPTS.") == 2
    candidate = source.replace(BLOCK, "", 1)
    assert source.replace(BLOCK, "", 1) == candidate and len(candidate.encode()) == 1407
    host = (ART / "preview-contract-host.luau").read_text(encoding="utf8")
    engine = (ART / "preview-offline-engine.luau").read_text(encoding="utf8")
    def payload(body, offline=False):
        return "return function()\n" + (engine + "\n" if offline else "") + "local function actual(game,workspace,require)\n" + body + "\nend\n" + host + "\nend\n"
    variants = {"before": source, "candidate": candidate,
                "publicNegative": candidate.replace("local PROMPTS = {", "local PROMPTS = {Level6DeveloperPreviewPrompt=true,", 1),
                "truthyNegative": candidate.replace("if ok and allowed == true then return end", "if ok and allowed then return end", 1)}
    assert variants["publicNegative"] != candidate and variants["truthyNegative"] != candidate
    canonical = load_canonical()
    compiler_rows = []
    compiled_body_rows = []
    native_payloads = {name: payload(body) for name, body in variants.items()}
    expected = None
    with tempfile.TemporaryDirectory(prefix="preview-c06-probe-") as directory:
        directory = Path(directory)
        binaries, dumps = {}, {}
        for name, body in variants.items():
            for kind, code in (("source", body), ("nativePayload", native_payloads[name]), ("offlinePayload", payload(body, True))):
                path = directory / (name + "-" + kind + ".luau")
                path.write_bytes(code.encode())
                for opt in (0, 1):
                    run = subprocess.run([str(COMPILER), "--binary", "-g0", f"-O{opt}", str(path)], capture_output=True, timeout=30)
                    assert run.returncode == 0, run.stderr.decode(errors="replace")
                    compiler_rows.append({"name": name, "kind": kind, "optimization": opt, "pass": True, "sourceSHA256": sha(code.encode())})
                    if name in ("before", "candidate") and kind == "source":
                        binary, metadata = canonical.canonical(run.stdout)
                        text = subprocess.run([str(COMPILER), "--text", "--dump-constants", "-g0", f"-O{opt}", str(path)], capture_output=True, check=True, timeout=30).stdout
                        binaries[(name, opt)] = binary
                        dumps[(name, opt)] = text
                        compiled_body_rows.append({"name": name, "optimization": opt, "functionCount": len(metadata), "rawBinarySHA256": sha(run.stdout), "canonicalBinarySHA256": sha(binary)})
        wrappers = "\n".join("local " + name + "=(function()\n" + payload(body, True) + "\nend)()" for name, body in variants.items())
        program = wrappers + '''
local a,b=before(),candidate()
assert(a.checks==b.checks and a.caseCount==b.caseCount and a.signature==b.signature,"Actual before/candidate filter behavior differs")
local aa,bb=before(),candidate()
assert(aa.checks==a.checks and aa.signature==a.signature and bb.checks==b.checks and bb.signature==b.signature,"Same runners differ on reentry")
for _,entry in {{publicNegative,"public L5/L6 prompts remain enabled"},{truthyNegative,"L4 initial entry is fail-closed truthy-string"}} do
 local ok,err=pcall(entry[1]);assert(not ok and tostring(err):find(entry[2],1,true),"Meaningful active prompt semantic mutant was not rejected")
end
print("CHECKS="..a.checks.." CASES="..a.caseCount)
'''
        path = directory / "offline-paired.luau"
        path.write_bytes(program.encode())
        run = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=30)
        assert run.returncode == 0, run.stdout + run.stderr
        match = re.search(r"CHECKS=(\d+) CASES=(\d+)", run.stdout)
        expected = {"checksPerVersion": int(match[1]), "casesPerVersion": int(match[2])}
        source_equivalence = [{"optimization": opt, "canonicalBinaryIdentical": binaries[("before", opt)] == binaries[("candidate", opt)],
                               "instructionConstantDumpIdentical": dumps[("before", opt)] == dumps[("candidate", opt)]} for opt in (0, 1)]
    # This no-op source rewrite changes the UserId read/branch opcodes; no
    # false bytecode-equivalence claim is made. Full-source contracts matter.
    assert (ROOT / FILE).read_bytes() == raw and (ROOT / "studio-sync-manifest.json").read_bytes() == manifest_raw
    wrapper_path = ROOT / "tools/cleanup_20261009/usher_private_locals_probe.luau"
    wrapper = wrapper_path.read_text(encoding="utf8")
    substitutions = {
        '__MongoTVUsherPrivateLocalsProbe20261010': '__MongoTVPreviewNoopProbe20261010',
        'usher probe': 'preview probe',
        'MongoTVCleanupUsherPrivateLocals_': 'MongoTVCleanupPreviewNoop_',
        'mongotv-usher-private-locals-native-contract-v1': 'mongotv-preview-noop-native-contract-v1',
        'Actual Usher chooseTarget/think/setBeamers/Stop contract against local-only perception/nav/capture/engine boundary tables. No live round, real asset, real multiplayer, streaming, respawn, teleport or performance certification.':
        'Actual full Level4PreviewPrompt source with test-owned native ProximityPrompt instances and real Enabled/DescendantAdded signals. Players/DevAccess/service results and descendant delivery are controlled boundaries. No live client, gameplay, real access/admission, multiplayer, streaming, teleport or performance certification.',
        'Actual Usher targeting/stun/Stop/failure/retry output changed': 'Actual preview filter/access/failure/reentry output changed',
        '{"ReasonNegative",payloads.reasonNegative,"reason still controls target mode holder"}': '{"PublicNegative",payloads.publicNegative,"public L5/L6 prompts remain enabled"}',
        '{"CooldownNegative",payloads.cooldownNegative,"held stun keeps existing cooldown"}': '{"TruthyNegative",payloads.truthyNegative,"L4 initial entry is fail-closed truthy-string"}',
        'Actual Usher semantic mutant was not rejected': 'Actual preview semantic mutant was not rejected',
    }
    for old, new in substitutions.items():
        assert old in wrapper, "Reviewed wrapper anchor changed: " + old
        wrapper = wrapper.replace(old, new)
    save(ART / ".gitattributes", b"* -text\n")
    save(PROPOSAL / "before.source.luau", before)
    save(PROPOSAL / "candidate.source.luau", candidate.encode())
    for name, body in native_payloads.items():
        save(PROPOSAL / (name + ".module.luau"), body.encode())
    save(PROPOSAL / "native-template.luau", wrapper.encode())
    receipt = {"schema": "preview-noop-proposal-v1", "finding": "C06", "file": FILE, "pass": True,
               "beforeSHA256": BEFORE, "candidateSHA256": sha(candidate.encode()), "beforeBytes": len(before), "candidateBytes": len(candidate.encode()), "removedBytes": 215,
               **expected, "pairedChecks": expected["checksPerVersion"] * 2, "reentryChecks": expected["checksPerVersion"] * 2,
               "semanticNegativeControls": 2, "compile": compiler_rows, "compiledBodies": compiled_body_rows, "sourceEquivalence": source_equivalence,
               "payloadHashes": {name: sha(body.encode()) for name, body in native_payloads.items()},
               "nativeTemplateSHA256": sha(wrapper.encode()), "reusedWrapperPath": wrapper_path.relative_to(ROOT).as_posix(), "reusedWrapperSHA256": sha(wrapper_path.read_bytes()),
               "toolSHA256": sha(Path(__file__).read_bytes()), "hostSHA256": sha((ART / "preview-contract-host.luau").read_bytes()), "offlineEngineSHA256": sha((ART / "preview-offline-engine.luau").read_bytes()),
               "canonicalParserSHA256": sha(Path(canonical.__file__).read_bytes()), "preparationRawTargetSHA256": sha(raw), "preparationManifestSHA256": sha(manifest_raw),
               "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
               "status": "Offline full-source tests pass; count-agnostic Root fresh-native binding, before/installed native ports and scoped CAS remain pending",
               "limits": "Offline fake signals do not certify native events. Root-run native runner uses actual test-owned prompts/property signals; fake Players/DevAccess/services are explicit controlled boundaries. No Play switch, live client/access/gameplay/multiplayer/streaming/teleport/performance pass."}
    save(PROPOSAL / "proposal.json", encoded(receipt))
    print(json.dumps({key: receipt[key] for key in ("pass", "beforeSHA256", "candidateSHA256", "removedBytes", "checksPerVersion", "casesPerVersion", "nativeCalls")}))


def bind(native_path, destination):
    assert destination is not None and not destination.exists(), "A new immutable binding directory is required"
    proof = json.loads((PROPOSAL / "proposal.json").read_bytes())
    assert sha(Path(__file__).read_bytes()) == proof["toolSHA256"]
    template = (PROPOSAL / "native-template.luau").read_text(encoding="utf8")
    assert sha(template.encode()) == proof["nativeTemplateSHA256"]
    payloads = {name: (PROPOSAL / (name + ".module.luau")).read_text(encoding="utf8") for name in proof["payloadHashes"]}
    assert all(sha(body.encode()) == proof["payloadHashes"][name] for name, body in payloads.items())
    native_raw = native_path.read_bytes()
    native = json.loads(native_raw)
    rows = native["rows"]
    scripts = [row for row in rows if row["className"] in ("ModuleScript", "Script", "LocalScript")]
    assert scripts and len({row["studioPath"] for row in scripts}) == len(scripts)
    manifest_raw = (ROOT / "studio-sync-manifest.json").read_bytes()
    manifest = json.loads(manifest_raw)
    assert manifest["counts"]["scripts"] == len(scripts), "Fresh complete census must match current mirror"
    wanted = {"StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt", "ReplicatedStorage.DevAccess"}
    originals = []
    for row in scripts:
        if row["studioPath"] not in wanted:
            continue
        current = next(item for item in manifest["items"] if item["studioPath"] == row["studioPath"])
        assert current["className"] == row["className"] and current["properties"] == row["properties"]
        assert current["attributes"] == row["attributes"] and current.get("tags", []) == row["tags"]
        assert row["sha256"] == current["sha256"] == sha(lf((ROOT / current["file"]).read_bytes()))
        copied = dict(row)
        copied["sourceSHA256"] = row["sha256"]
        originals.append(copied)
    assert len(originals) == 2
    originals.sort(key=lambda row: row["studioPath"] != "StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt")
    assert originals[0]["className"] == "LocalScript" and originals[0]["sourceSHA256"] == BEFORE
    expected = {"nativeScriptCount": len(scripts), "contractChecks": proof["checksPerVersion"], "originals": originals}
    compile_rows, codes = [], {}
    with tempfile.TemporaryDirectory(prefix="preview-native-binding-") as directory:
        for phase in ("before", "installed"):
            values = json.loads(json.dumps(expected))
            if phase == "installed":
                values["originals"][0]["sourceSHA256"] = proof["candidateSHA256"]
            code = template.replace("__EXPECTED__", lua_literal(json.dumps(values, ensure_ascii=False)))
            code = code.replace("__PAYLOADS__", lua_literal(json.dumps(payloads, ensure_ascii=False))).replace("__INSTALLED__", str(phase == "installed").lower())
            assert "__EXPECTED__" not in code and "__PAYLOADS__" not in code and "__INSTALLED__" not in code
            path = Path(directory) / (phase + ".luau")
            path.write_bytes(code.encode())
            for opt in (0, 1):
                run = subprocess.run([str(COMPILER), "--binary", "-g0", f"-O{opt}", str(path)], capture_output=True, timeout=30)
                assert run.returncode == 0, run.stderr.decode(errors="replace")
                compile_rows.append({"phase": phase, "optimization": opt, "pass": True})
            codes[phase] = code
    assert (ROOT / "studio-sync-manifest.json").read_bytes() == manifest_raw and native_path.read_bytes() == native_raw
    for phase, code in codes.items():
        save(destination / ("native-" + phase + ".luau"), code.encode())
    save(destination / "binding.json", encoded({"pass": True, "nativeInputPath": native_path.as_posix(), "nativeInputSHA256": sha(native_raw),
                                                "manifestSHA256": sha(manifest_raw), "expected": expected, "compile": compile_rows,
                                                "nativeCodeHashes": {phase: sha(code.encode()) for phase, code in codes.items()},
                                                "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0}))
    print(json.dumps({"pass": True, "nativeScriptCount": len(scripts), "nativeCalls": 0, "destination": destination.as_posix()}))


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--bind-native", type=Path)
    parser.add_argument("--destination", type=Path)
    args = parser.parse_args()
    if args.bind_native:
        bind(args.bind_native, args.destination)
    else:
        assert args.destination is None
        prepare()
