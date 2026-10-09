"""V4 pre-transaction rejection ports; no native calls or canonical writes."""
from pathlib import Path
import sys, tempfile, json, argparse
from unittest import mock
ROOT = Path(__file__).resolve().parents[4]
sys.dont_write_bytecode = True
sys.path.insert(0, str(ROOT / "tools/cleanup_20261009"))
import retire_external_mirror_sources_v4 as actual

def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.receipt:
        assert not args.receipt.exists(), "Refuse historical receipt overwrite"
    head_raw = actual.PINNED_HEAD.read_bytes()
    cases = []
    for label in ("different HEAD with identical manifest", "changed portable HEAD input"):
        with tempfile.TemporaryDirectory(prefix=".s06-head-cas-", dir=ROOT) as directory:
            fixture = Path(directory)
            manifest = fixture / "studio-sync-manifest.json"
            manifest.write_bytes(head_raw)
            pinned = fixture / "pinned.json"
            pinned.write_bytes(head_raw + (b"\n" if label == "changed portable HEAD input" else b""))
            checkpoint, evidence = fixture / "checkpoint", fixture / "evidence"
            def check_output(command, **kwargs):
                assert kwargs == {"cwd": fixture}
                if command == ["git", "rev-parse", "HEAD"]:
                    revision = "f" * 40 if label == "different HEAD with identical manifest" else actual.EXPECTED_HEAD_REVISION
                    return (revision + "\n").encode()
                assert command == ["git", "show", "HEAD:studio-sync-manifest.json"]
                return head_raw
            with mock.patch.multiple(actual, ROOT=fixture, CHECKPOINT=checkpoint, EVIDENCE=evidence, PINNED_HEAD=pinned), \
                 mock.patch.object(actual.subprocess, "check_output", side_effect=check_output), \
                 mock.patch.object(actual, "StudioMcpClient") as client:
                try:
                    actual.main()
                except AssertionError as error:
                    expected = "Current HEAD revision changed" if label == "different HEAD with identical manifest" else "Portable HEAD input differs"
                    assert expected in str(error)
                else:
                    raise AssertionError("Changed HEAD input was accepted")
                client.assert_not_called()
            assert manifest.read_bytes() == head_raw and not checkpoint.exists() and not evidence.exists()
            cases.append({"name": label, "pass": True, "nativeCalls": 0, "canonicalWrites": 0})
    receipt = {"schema": "s06-v4-head-cas-negative-v1", "pass": True, "cases": cases,
               "wrapperSHA256": actual.preflight.sha(Path(actual.__file__).read_bytes()),
               "testSHA256": actual.preflight.sha(Path(__file__).read_bytes())}
    if args.receipt:
        actual.save_new(args.receipt, actual.preflight.encode(receipt))
    print(json.dumps(receipt))

if __name__ == "__main__":
    main()
