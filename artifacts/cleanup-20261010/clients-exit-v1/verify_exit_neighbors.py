"""Run the existing entire B6/B7 suite with immutable target inputs only.

Path reader substitution is restricted to this single Exit Source. Existing
production implementation and assertions remain unchanged. No Studio/imported
asset/physical input or multiplayer certification is inferred.
"""
from pathlib import Path
import argparse
import contextlib
import hashlib
import importlib.util
import io
import json
import os
import re
import sys
from unittest.mock import patch

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
TARGET = ROOT / "StarterPlayer/StarterPlayerScripts/Round Exit Client.LocalScript.lua"
sys.path.insert(0, str(ROOT / "tools/tests"))
import test_hud_b6_b7 as actual


def main(destination=None, verify_installed=False):
    destination = destination or HERE / "neighbor-gates-v1.json"
    assert not destination.exists(), "Preserve immutable receipt"
    manifest = ROOT / "studio-sync-manifest.json"
    starting = {path: path.read_bytes() for path in (TARGET, manifest)}
    proposal = json.loads((HERE/"proposal-v1/proposal.json").read_bytes())
    digest = lambda raw: hashlib.sha256(raw).hexdigest()
    for phase,key in (("before","beforeSHA256"),("candidate","candidateSHA256")):
        assert digest((HERE/"proposal-v1"/(phase+".source.luau")).read_bytes()) == proposal[key]
    if verify_installed:
        assert digest(starting[TARGET].replace(b"\r\n",b"\n")) == proposal["candidateSHA256"], "Actual installed Source differs"
        rows=[row for row in json.loads(starting[manifest])["items"] if row.get("file") == proposal["file"]]
        assert len(rows)==1 and rows[0]["sha256"]==proposal["candidateSHA256"] and rows[0]["bytes"]==proposal["candidateBytes"]
    for row in proposal["closure"]:
        if row["file"] == proposal["file"]:continue
        assert digest((ROOT/row["file"]).read_bytes()) == row["rawSHA256"], "Dependency changed; rebaseline from native: "+row["file"]
    read = Path.read_text
    cases = []
    for phase in ("before", "candidate"):
        raw = (HERE / "proposal-v1" / (phase + ".source.luau")).read_bytes()
        def scoped_read(self, *args, **kwargs):
            if self.resolve() == TARGET.resolve():
                return raw.decode("utf8")
            return read(self, *args, **kwargs)
        output = io.StringIO()
        with patch.object(Path, "read_text", scoped_read), patch.dict(os.environ, {
            "LUAU_BIN": "C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe"}), contextlib.redirect_stdout(output):
            actual.main()
        text = output.getvalue()
        matched = re.search(r"B6/B7: (\d+) checks passed", text)
        assert matched, text
        cases.append({"phase": phase, "pass": True, "checks": int(matched[1]),
            "sourceSHA256": hashlib.sha256(raw).hexdigest(), "stdout": text.strip()})
    assert cases[0]["checks"] == cases[1]["checks"] == 92
    assert all(path.read_bytes() == before for path, before in starting.items()), "Canonical source/manifest changed"
    proof = {"pass": True, "actualRunner": "tools/tests/test_hud_b6_b7.py", "cases": cases,"verifyInstalledRequested":verify_installed,
        "installedSourceVerified":verify_installed,
        "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
        "limits": "Existing unchanged full B6/B7 assertions/production sources with single Source-reader substitution and controlled fake engine/imported historical fixture/input/transport/UIDevice boundaries. Not native asset, gameplay, hardware, multiplayer or streaming certificate."}
    destination.parent.mkdir(parents=True,exist_ok=True)
    with destination.open("xb") as stream:
        stream.write((json.dumps(proof, indent=2) + "\n").encode())
    print(json.dumps({"pass": True, "before": cases[0]["checks"], "candidate": cases[1]["checks"], "nativeCalls": 0}))


if __name__ == "__main__":
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt",type=Path)
    parser.add_argument("--verify-installed",action="store_true")
    args=parser.parse_args()
    main(args.receipt,args.verify_installed)
