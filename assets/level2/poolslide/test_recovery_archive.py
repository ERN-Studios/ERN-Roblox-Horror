"""Isolated filesystem-only tests for source-pack restore safety and integrity."""
import gzip
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import tarfile
import tempfile
import unittest


REPO = Path(__file__).resolve().parents[3]
spec = importlib.util.spec_from_file_location("poolslide_restore", REPO / "tools/restore-poolslide-assets.py")
restore_tool = importlib.util.module_from_spec(spec)
spec.loader.exec_module(restore_tool)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def make_pack(directory, members=None, declared=None):
    members = members if members is not None else [("nested/file with spaces.txt", b"verified content", None)]
    stream = io.BytesIO()
    with gzip.GzipFile(fileobj=stream, mode="wb", mtime=0) as compressed:
        with tarfile.open(fileobj=compressed, mode="w") as archive:
            for name, raw, kind in members:
                entry = tarfile.TarInfo(name)
                if kind:
                    entry.type = kind
                    entry.linkname = "nested/file with spaces.txt"
                else:
                    entry.size = len(raw)
                archive.addfile(entry, io.BytesIO(raw) if not kind else None)
    raw_archive = stream.getvalue()
    directory.mkdir()
    (directory / "part").write_bytes(raw_archive)
    records = declared if declared is not None else [
        {"path": name, "bytes": len(raw), "sha256": sha(raw)} for name, raw, _ in members]
    manifest = {"schema": "poolslide-source-pack-v1", "files": records,
                "parts": [{"path": "part", "bytes": len(raw_archive), "sha256": sha(raw_archive)}],
                "archiveBytes": len(raw_archive), "archiveSha256": sha(raw_archive),
                "verifiedSourceFileCount": len(records)}
    (directory / "manifest.json").write_text(json.dumps(manifest))
    return manifest


class RestoreTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="poolslide-restore-test-")
        self.root = Path(self.temp.name)
        self.pack = self.root / "pack"

    def tearDown(self):
        self.temp.cleanup()

    def test_verify_and_restore_exact_bytes(self):
        make_pack(self.pack)
        result = restore_tool.restore(self.pack, None)
        self.assertEqual(result["verifiedFiles"], 1)
        output = self.root / "output"
        restore_tool.restore(self.pack, output)
        self.assertEqual((output / "nested/file with spaces.txt").read_bytes(), b"verified content")

    def test_existing_destination_is_untouched(self):
        make_pack(self.pack)
        output = self.root / "output"
        output.mkdir()
        (output / "sentinel").write_text("keep")
        with self.assertRaises(FileExistsError):
            restore_tool.restore(self.pack, output)
        self.assertEqual((output / "sentinel").read_text(), "keep")

    def test_corrupted_part_fails_before_output(self):
        make_pack(self.pack)
        (self.pack / "part").write_bytes(b"corrupt")
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, self.root / "output")
        self.assertFalse((self.root / "output").exists())

    def test_wrong_file_hash_fails_before_output(self):
        make_pack(self.pack, declared=[{"path": "nested/file with spaces.txt", "bytes": 16, "sha256": "0" * 64}])
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, self.root / "output")
        self.assertFalse((self.root / "output").exists())

    def test_unsafe_paths_rejected(self):
        for name in ("../escape", "/absolute", ".", "", "nested/../escape", "a//b", "C:/x", "a\\b", "a\x00b"):
            with self.subTest(name=name), self.assertRaises(ValueError):
                restore_tool.safe_relative(name)

    def test_symlink_rejected(self):
        make_pack(self.pack, members=[("link", b"", tarfile.SYMTYPE)])
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, self.root / "output")
        self.assertFalse((self.root / "output").exists())

    def test_duplicate_member_rejected(self):
        members = [("same", b"a", None), ("same", b"a", None)]
        make_pack(self.pack, members, [{"path": "same", "bytes": 1, "sha256": sha(b"a")}])
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, None)

    def test_unexpected_member_rejected(self):
        make_pack(self.pack, declared=[])
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, None)

    def test_missing_member_rejected(self):
        make_pack(self.pack, members=[], declared=[{"path": "missing", "bytes": 0, "sha256": sha(b"")}])
        with self.assertRaises(ValueError):
            restore_tool.restore(self.pack, None)


if __name__ == "__main__":
    unittest.main(verbosity=2)
