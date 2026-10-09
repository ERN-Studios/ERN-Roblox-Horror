"""Read-only portable N01 input/receipt and generated-wrapper compile gate.

No Studio call or historical output regeneration. Altered sources live only
inside an automatically removed OS-temp copy. Prints a fresh offline report.
"""
import argparse
import ast
import hashlib
import importlib.util
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
from types import SimpleNamespace

sys.dont_write_bytecode = True

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[1]
TOOL = HERE / "run_N01_pair_probe.py"
RECEIPTS = {
    "pair-before": "B06-pair-before.json",
    "pair-current": "B06-pair-current.json",
    "touch-probe-before": "B06-touch-before.json",
    "touch-probe-current": None,
    "touch-probe-reset": "B06-touch-reset.json",
}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--compiler", default=os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile"))
    args = parser.parse_args()
    if not args.compiler:
        parser.error("Set LUAU_COMPILE_BIN or --compiler to Luau0.737 luau-compile")
    spec = importlib.util.spec_from_file_location("archived_pair_tool", TOOL)
    tool = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(tool)
    checks = 0

    def check(value, message):
        nonlocal checks
        assert value, message
        checks += 1

    calls = []

    def forbidden(*args, **kwargs):
        calls.append("StudioMcpClient")
        raise AssertionError("offline port attempted a Studio call")

    tool.StudioMcpClient = forbidden
    tool.find_mcp_batch = forbidden
    tool.select_studio = forbidden
    index_path = tool.PROOF_DIR / "index.json"
    index = json.loads(index_path.read_text(encoding="utf8"))
    protected = {TOOL: TOOL.read_bytes(), index_path: index_path.read_bytes()}
    sources = {}
    original_inputs = 0
    receipt_count = 0
    for row in index["files"]:
        suffix = row["file"].removeprefix("UIRegression.N01.").removesuffix(".lua")
        check(suffix in RECEIPTS and row["receipt"] == RECEIPTS[suffix], "receipt inventory drift")
        path = tool.PROOF_DIR / row["file"]
        raw = path.read_bytes()
        protected[path] = raw
        source = tool.load_probe(suffix)
        check(source.encode("utf8") == raw, "probe reader altered raw input")
        check(hashlib.sha256(raw).hexdigest() == row["rawSha256"], "raw input hash")
        check(hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest() == row["lfSha256"], "LF input hash")
        sources[suffix] = source
        local = ROOT / row["historicalLocalInput"]
        if local.exists():
            protected[local] = local.read_bytes()
            check(protected[local] == raw, "original local checkpoint differs from archive")
            original_inputs += 1
        if row["receipt"]:
            receipt = HERE / row["receipt"]
            receipt_raw = receipt.read_bytes()
            protected[receipt] = receipt_raw
            check(hashlib.sha256(receipt_raw.replace(b"\r\n", b"\n")).hexdigest() == row["receiptLfSha256"], "receipt content changed")
            data = tool.unwrap(receipt_raw.decode("utf8"))
            check(data["probeSha256"] == row["lfSha256"], "receipt source identity differs")
            check(data["ok"] and data["originalSourcesUnchanged"] and data["temporaryDestroyed"], "historical receipt ownership failed")
            receipt_count += 1
        else:
            check(suffix == "touch-probe-current" and "no saved native" in row["receiptNote"], "missing native receipt must remain explicit")
    check(len(sources) == 5 and receipt_count == 4, "five inputs / four recorded receipt hashes")

    original_dir = tool.PROOF_DIR
    rejected = 0
    with tempfile.TemporaryDirectory(prefix="N01-proof-negative-") as directory:
        copy = Path(directory)
        for path in original_dir.iterdir():
            if path.is_file():
                shutil.copyfile(path, copy / path.name)
        tool.PROOF_DIR = copy
        try:
            for suffix in sources:
                path = copy / ("UIRegression.N01." + suffix + ".lua")
                original = path.read_bytes()
                path.write_bytes(original + b"\n-- altered proof\n")
                try:
                    tool.load_probe(suffix)
                except AssertionError as error:
                    check("hash drift" in str(error), "altered proof rejected for content identity")
                    rejected += 1
                else:
                    raise AssertionError("changed proof accepted: " + suffix)
                finally:
                    path.write_bytes(original)
            changed = json.loads((copy / "index.json").read_text(encoding="utf8"))
            changed["files"][0]["rawSha256"] = "0" * 64
            (copy / "index.json").write_text(json.dumps(changed), encoding="utf8")
            try:
                tool.load_probe("pair-before")
            except AssertionError as error:
                check("hash drift" in str(error), "changed index digest rejected")
                rejected += 1
            else:
                raise AssertionError("changed index accepted")
        finally:
            tool.PROOF_DIR = original_dir

    old_argv = sys.argv[:]
    try:
        sys.argv = [str(TOOL), "pair-before"]
        try:
            tool.main()
        except AssertionError as error:
            check("historical receipt already exists" in str(error), "existing receipt fails before native call")
        else:
            raise AssertionError("historical receipt overwrite accepted")
        sys.argv = [str(TOOL), "pair-before", "--receipt-label", "../invalid"]
        try:
            tool.main()
        except AssertionError as error:
            check("unsafe receipt label" in str(error), "unsafe output label rejected before native call")
        else:
            raise AssertionError("unsafe output label accepted")
    finally:
        sys.argv = old_argv

    tree = ast.parse(TOOL.read_text(encoding="utf8"), filename=str(TOOL))
    ast.parse(Path(__file__).read_text(encoding="utf8"), filename=__file__)
    expressions = [node.value for node in ast.walk(tree) if isinstance(node, ast.Assign)
                   and isinstance(node.value, ast.JoinedStr)
                   and any(isinstance(target, ast.Name) and target.id == "code" for target in node.targets)]
    check(len(expressions) == 1, "actual generated-code expression remains unique")
    compiled = 0
    with tempfile.TemporaryDirectory(prefix="N01-proof-compile-") as directory:
        for suffix, source in sources.items():
            lane = "scenarios" if suffix.startswith("pair-") else "touch"
            label = suffix.rsplit("-", 1)[1]
            phase = "pair-" + label
            environment = {"__builtins__": {}, "luau_string": tool.luau_string,
                           "hashlib": hashlib, "source": source, "label": label,
                           "ui_hash": "0" * 64, "hud_hash": "1" * 64,
                           "args": SimpleNamespace(phase=phase),
                           "entrypoint": "CleanupScenarioPair" if lane == "scenarios" else "CleanupTouchLifecycleProbe"}
            wrapper = eval(compile(ast.Expression(expressions[0]), str(TOOL), "eval"), environment)
            for kind, body in (("proof", source), ("wrapper", wrapper)):
                path = Path(directory) / (suffix + "." + kind + ".luau")
                path.write_text(body, encoding="utf8")
                for optimization in (0, 1):
                    result = subprocess.run([args.compiler, "--null", "-O" + str(optimization), str(path)], capture_output=True, timeout=30)
                    check(result.returncode == 0, result.stderr.decode(errors="replace"))
                    compiled += 1
    check(not calls, "no Studio client initialized")
    check(all(path.read_bytes() == raw for path, raw in protected.items()), "original tool/index/inputs/receipts/checkpoints changed")
    print(json.dumps({"status": "PASS offline archive port only", "checks": checks,
                      "inputCount": 5, "receiptHashesMatched": receipt_count,
                      "unrecordedNativeReceipt": "touch-probe-current; historical input only",
                      "alteredInputOrIndexControlsRejected": rejected,
                      "receiptOverwriteAndUnsafeLabelControlsRejected": 2,
                      "pythonAst": "2/2 PASS", "fullProofAndActualWrapperCompile": compiled,
                      "studioCalls": len(calls), "productionWrites": 0,
                      "historicalReceiptsAndInputsUnchanged": True,
                      "localOriginalInputsCheckedIfPresent": original_inputs,
                      "toolSha256": hashlib.sha256(TOOL.read_bytes()).hexdigest(),
                      "verifierSha256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
                      "indexRawSha256": hashlib.sha256(index_path.read_bytes()).hexdigest()}, indent=2))


if __name__ == "__main__":
    main()
