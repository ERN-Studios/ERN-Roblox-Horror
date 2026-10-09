"""Bounded local guard fixtures; no Studio connection or real runtime mirror write."""
from pathlib import Path
import json
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
import promote_verified_mirrors as promotion


def main():
    checks = 0
    def check(condition):
        nonlocal checks
        assert condition
        checks += 1
    def rejects(callback):
        nonlocal checks
        try: callback()
        except AssertionError: checks += 1
        else: raise AssertionError("Unexpected local source mutation accepted")
    # All files are small synthetic strings, never copies of owner source.
    with tempfile.TemporaryDirectory(prefix="promotion-guard-fixture-",dir=promotion.HERE) as folder:
        owned = Path(folder).resolve()
        assert owned.is_relative_to(promotion.HERE)
        destination = owned / "Fixture.LocalScript.lua"
        raw_path = owned / "raw.fixture"
        before, after = b"print('before')\n", b"print('after')\n"
        raw_path.write_bytes(after)
        row = {"destination":destination,"nativeBefore":before,"raw":after,"rawPath":raw_path,
            "captured":{"rawFile":"synthetic-fixture"}}
        destination.write_bytes(before)
        observed, record = promotion.local_snapshot(row)
        check(observed == before and record["acceptedLocalState"] == "exact-native-before" and record["localBeforeRawSha256"] == promotion.digest(before))
        destination.write_bytes(before.replace(b"\n",b"\r\n"))
        observed, record = promotion.local_snapshot(row)
        check(record["acceptedLocalState"] == "native-before-with-CRLF-only" and record["localBeforeRawSha256"] != record["localBeforeCanonicalSha256"])
        destination.write_bytes(after)
        observed, record = promotion.local_snapshot(row)
        check(record["acceptedLocalState"] == "already-exact-native-after" and promotion.copy_exact(row,observed) is False)
        destination.write_bytes(after.replace(b"\n",b"\r\n"))
        observed, record = promotion.local_snapshot(row)
        check(record["acceptedLocalState"] == "native-after-with-CRLF-only")
        check(promotion.copy_exact(row,observed) and destination.read_bytes() == after)
        destination.write_bytes(b"print('foreign work')\n")
        rejects(lambda:promotion.local_snapshot(row))
        check(destination.read_bytes() == b"print('foreign work')\n")
        destination.unlink()
        rejects(lambda:promotion.local_snapshot(row))
        row["nativeBefore"] = None
        observed, record = promotion.local_snapshot(row)
        check(observed is None and record["acceptedLocalState"] == "absent-new-mirror" and record["localBeforeRawSha256"] is None)
        destination.write_bytes(b"concurrent new mirror")
        rejects(lambda:promotion.copy_exact(row,observed))
        check(destination.read_bytes() == b"concurrent new mirror")
        destination.unlink()
        check(promotion.copy_exact(row,None) and destination.read_bytes() == after)
        row["nativeBefore"] = before
        destination.write_bytes(before)
        observed, _ = promotion.local_snapshot(row)
        destination.write_bytes(b"concurrent edited source")
        rejects(lambda:promotion.copy_exact(row,observed))
        check(destination.read_bytes() == b"concurrent edited source")
        destination.write_bytes(before)
        observed, _ = promotion.local_snapshot(row)
        raw_path.write_bytes(b"modified export payload")
        rejects(lambda:promotion.copy_exact(row,observed))
        check(destination.read_bytes() == before)
        check(not list(owned.glob(".optimization-20261009-*")))
        raw_path.write_bytes(after)
        check(promotion.copy_exact(row,before) and destination.read_bytes() == after)
        check(not list(owned.glob(".optimization-20261009-*")))
    native = promotion.native_cas_code(promotion.native_rows())
    code_file = promotion.HERE / "promotion-native-read-cas.luau"
    code_file.write_bytes(native.encode("utf-8"))
    compiler = str(Path(os.environ["LUAU_BIN"]).with_name("luau-compile.exe"))
    result = subprocess.run([compiler,str(code_file)],capture_output=True,text=True)
    check(result.returncode == 0)
    receipt = {"localGuardChecks":checks,"syntheticLocalFixturesOnly":True,"studioConnected":False,
        "realRuntimeMirrorsWritten":False,"nativeBackup":False,"nativeCasCompiled":True,
        "nativeCasCodeSha256":promotion.digest(native.encode("utf-8")),"compiler":compiler}
    (promotion.HERE / "promotion-preparation-result.json").write_text(json.dumps(receipt,indent=2)+"\n",encoding="utf-8")
    print(f"{checks} scoped local guards passed; exact seven-source native read CAS compiled; no Studio connection/runtime mirror writes.")


if __name__ == "__main__": main()
