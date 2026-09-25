"""Every mirrored script must compile the way Studio compiles it.

STUDIO_COMPILE_LIMITS_20260924. luau-compile's default -O1 folds a local that
holds a constant and is never reassigned, so it does not count toward Luau's
200-locals-per-function limit. Studio counts it: on 2026-09-24 ZyntraMonetization
compiled offline at -O1 and failed the push tool's compile probe with
"Out of local registers when trying to allocate salesImportReadback: exceeded
limit 200" -- exactly what luau-compile reports at -O0. So this compiles every
manifest script at -O0, wrapped the way tools/push_repo_to_studio.py wraps the
probe (`return function() <source> end`), and first proves on a synthetic chunk
that -O0 catches the limit -O1 misses. The headroom of the scripts known to sit
near the limit is printed so a shrinking margin is visible before it fails.

Needs luau-compile: LUAU_COMPILE, or next to LUAU_BIN, or on PATH. This is not
the Studio probe itself; tools/studio_compile_probe.luau and the push tool's
compile check remain the authority.
"""

import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
TIGHT = ["ServerScriptService/ZyntraMonetization.Script.lua", "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"]


def find_compiler():
    explicit = os.environ.get("LUAU_COMPILE")
    if explicit:
        return explicit
    luau = os.environ.get("LUAU_BIN")
    if luau:
        for name in ("luau-compile.exe", "luau-compile"):
            candidate = Path(luau).with_name(name)
            if candidate.exists():
                return str(candidate)
    return shutil.which("luau-compile")


def compile_source(compiler, directory, source, level="-O0"):
    path = Path(directory) / "probe.luau"
    path.write_text("return function()\n" + source + "\nend", encoding="utf-8")
    result = subprocess.run([compiler, level, "--null", str(path)], capture_output=True, text=True, timeout=60)
    return result.returncode == 0, (result.stdout + result.stderr).strip()


def headroom(compiler, directory, source, limit=40):
    for extra in range(limit + 1):
        pad = "".join(f"local __pad{i} = workspace\n" for i in range(extra + 1))
        if not compile_source(compiler, directory, pad + source)[0]:
            return extra
    return f">{limit}"


def main():
    compiler = find_compiler()
    if not compiler:
        raise SystemExit("Set LUAU_COMPILE (or LUAU_BIN beside luau-compile); no scripts were compiled.")
    manifest = json.loads((ROOT / "studio-sync-manifest.json").read_text(encoding="utf-8"))
    files = [item["file"] for item in manifest["items"] if item.get("file", "").endswith(".lua")]
    assert files, "manifest lists no scripts"
    with tempfile.TemporaryDirectory(prefix="studio-compile-") as directory:
        # The check must catch what -O1 misses: 201 constant locals in one function.
        synthetic = "".join(f"local c{i} = {i}\n" for i in range(201))
        caught, message = compile_source(compiler, directory, synthetic, "-O0")
        assert not caught and "exceeded limit 200" in message, "-O0 must refuse 201 constant locals"
        assert compile_source(compiler, directory, synthetic, "-O1")[0], \
            "-O1 folding them is why an -O1 compile is not enough"

        failures = []
        for rel in files:
            ok, message = compile_source(compiler, directory, (ROOT / rel).read_text(encoding="utf-8"))
            if not ok:
                failures.append(f"{rel}: {message.splitlines()[-1] if message else '?'}")
        for rel in TIGHT:
            if (ROOT / rel).exists():
                room = headroom(compiler, directory, (ROOT / rel).read_text(encoding="utf-8"))
                print(f"  {rel}: {room} more top-level local(s) before the Studio limit")
    if failures:
        raise SystemExit("Scripts Studio would refuse to compile:\n  " + "\n  ".join(failures))
    print(f"studio compile limits: {len(files)} scripts compile at -O0 in the probe wrapper; "
          "-O0 proven to catch the 200-local limit that -O1 folds away")


if __name__ == "__main__":
    main()
