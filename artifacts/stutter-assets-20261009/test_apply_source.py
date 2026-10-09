"""Offline temporary fixtures only; never contacts Studio or writes real mirrors."""
import copy
import importlib.util
import json
from pathlib import Path
import tempfile
import unittest

SPEC = importlib.util.spec_from_file_location("task_apply_source", Path(__file__).with_name("apply_source.py"))
helper = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(helper)


class ApplySourceTests(unittest.TestCase):
    def test_empty_lua_attributes_and_callback_guards(self):
        native = {"path": "ServerScriptService.One", "class": "ModuleScript",
                  "properties": {"Archivable": True, "LinkedSource": ""}, "attributes": []}
        code = helper.install_code(native, "return 1\n", "return 2\n")
        self.assertIn('assert(count==0,"Attributes changed")', code)
        callback = code.split("SES:UpdateSourceAsync(s,function(current)", 1)[1].split("end)", 1)[0]
        self.assertIn("baselineGuard()", callback)
        self.assertIn('assert(current==before,"Callback baseline changed")', callback)
        self.assertIn("assert(resolve()==s", code)
        self.assertIn('assert(SES:GetEditorSource(s)==before', code)
        self.assertIn('assert(SES:GetEditorSource(s)==after', code)

    def test_unsupported_metadata_rejected_before_install(self):
        native = {"path": "ServerScriptService.One", "class": "ModuleScript",
                  "properties": {"Archivable": True, "LinkedSource": ""}, "attributes": [1]}
        with self.assertRaises(AssertionError):
            helper.install_code(native, "old", "new")
        native["attributes"] = {"Typed": {"type": "Vector3"}}
        with self.assertRaises(AssertionError):
            helper.install_code(native, "old", "new")
        with self.assertRaises(AssertionError):
            helper.unique([{"path": "one"}, {"path": "one"}], lambda r: True, "baseline")

    def fixture(self, root):
        rel = "Sources/One.lua"
        (root / "Sources").mkdir()
        mirror = root / rel
        mirror.write_bytes(b"prior mirror\r\n")
        manifest = {"counts": {"total": 2}, "unrelatedDirtyTopField": "keep",
                    "items": [{"file": rel, "studioPath": "ServerScriptService.One", "className": "ModuleScript",
                               "bytes": 1, "sha256": "old", "status": "pending-studio-push", "studioSha256Before": "old"},
                              {"file": "Sources/Other.lua", "status": "pending-studio-push", "unrelatedDirty": [1, 2]}]}
        raw = (json.dumps(manifest, indent=2) + "\n").encode()
        (root / "studio-sync-manifest.json").write_bytes(raw)
        return rel, mirror, manifest, raw

    def test_export_changes_only_named_manifest_entry(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            rel, mirror, manifest, raw = self.fixture(root)
            original = copy.deepcopy(manifest)
            result = helper.export_verified(root, rel, raw, mirror.read_bytes(), "return 2\n")
            actual = json.loads((root / "studio-sync-manifest.json").read_bytes())
            self.assertEqual(mirror.read_bytes(), b"return 2\n")
            self.assertEqual(actual["items"][1], original["items"][1])
            actual["items"][0] = original["items"][0]
            self.assertEqual(actual, original)
            self.assertEqual(result["mirrorSha256"], helper.digest(b"return 2\n"))

    def test_concurrent_manifest_or_mirror_change_blocks_all_writes(self):
        for change in ("mirror", "manifest"):
            with self.subTest(change=change), tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                rel, mirror, manifest, raw = self.fixture(root)
                mirror_before = mirror.read_bytes()
                changed = mirror if change == "mirror" else root / "studio-sync-manifest.json"
                changed.write_bytes(b"concurrent developer work")
                observed_mirror = mirror.read_bytes()
                observed_manifest = (root / "studio-sync-manifest.json").read_bytes()
                with self.assertRaises(AssertionError):
                    helper.export_verified(root, rel, raw, mirror_before, "return 2\n")
                self.assertEqual(mirror.read_bytes(), observed_mirror)
                self.assertEqual((root / "studio-sync-manifest.json").read_bytes(), observed_manifest)


if __name__ == "__main__":
    unittest.main()
