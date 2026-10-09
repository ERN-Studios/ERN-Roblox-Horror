"""Offline transfer, scope, lifecycle and native-request contracts; no Studio/network/assets."""
from __future__ import annotations

import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import types
import unittest
from unittest.mock import patch

FILE = Path(__file__).with_name("retired_authoring_archive_receiver.py")
spec = importlib.util.spec_from_file_location("s04_receiver_offline", FILE)
receiver = importlib.util.module_from_spec(spec)
spec.loader.exec_module(receiver)


class Contracts(unittest.TestCase):
    def setUp(self):
        self.directory = tempfile.TemporaryDirectory(prefix="mongodb-s04-offline-")
        self.base = Path(self.directory.name)
        self.base_patch = patch.object(receiver, "BASE", self.base)
        self.base_patch.start()
        self.native = b"SYNTHETIC OFFLINE BYTES: NOT A ROBLOX ARCHIVE\x00" * 13000
        self.archive = receiver.Archive(self.base / "retired-authoring-archive-v1", "capture", 51, 2)

    def tearDown(self):
        self.base_patch.stop()
        self.directory.cleanup()

    def facts(self):
        nodes, roots = [], []
        groups = (
            {"Folder": 38, "StringValue": 59}, {"Folder": 38, "StringValue": 59},
            {"Folder": 41, "StringValue": 63}, {"Folder": 41, "StringValue": 63},
            {"Folder": 207, "Model": 283, "Part": 51, "MeshPart": 498, "SurfaceAppearance": 176},
        )
        for name, count, classes in zip(receiver.NAMES, receiver.ROOT_COUNTS, groups):
            root_id = len(nodes) + 1
            roots.append({"name": name, "class": "Folder", "instances": count, "index": root_id})
            for kind, amount in classes.items():
                for _ in range(amount):
                    index = len(nodes) + 1
                    nodes.append({"id": index, "parent": 0 if index == root_id else root_id,
                                  "name": name if index == root_id else f"fixture{index}", "class": kind,
                                  "archivable": True, "attributes": [], "properties": {}, "tags": [], "children": []})
            nodes[root_id - 1]["children"] = list(range(root_id + 1, root_id + count))
        return {"schema": receiver.SCHEMA, "stage": "precompletion", "passed": False, "placeId": 131311258779917, "universeId": 10559217407,
                "scopeNames": list(receiver.NAMES), "rootCount": 5, "totalInstances": 1617,
                "captureId": self.archive.capture_id, "noOriginalMutation": True, "deletionApproved": False,
                "nativeSHA256": receiver.digest(self.native), "nativeBytes": len(self.native),
                "serverStorageRootCount": 51, "sourceCount": 2,
                "forest": {"instanceCount": 1617, "scriptCount": 0, "roots": roots, "nodes": nodes},
                "sourceInventory": [{"path": f"Fixture.Module{i}", "class": "ModuleScript", "bytes": 1,
                                     "sourceSHA256": receiver.digest(bytes([i])), "directRetiredNameMatches": []}
                                    for i in range(2)], "references": {"externalReadable": []}}

    def upload(self, facts=None, *, finalize=True):
        payloads = {"native": self.native, "facts": json.dumps(facts or self.facts()).encode()}
        metadata = {}
        for kind, raw in payloads.items():
            pieces = [raw[i:i + receiver.PART_BYTES] for i in range(0, len(raw), receiver.PART_BYTES)]
            for i, piece in enumerate(pieces):
                self.archive.post(f"/part/{kind}/{i}", piece, self.archive.capture_id)
            metadata[kind] = {"parts": len(pieces), "bytes": len(raw), "sha256": receiver.digest(raw)}
        if finalize:
            self.archive.post("/finalize", json.dumps(metadata).encode(), self.archive.capture_id)
        return metadata

    def final_capture(self, passed=True):
        self.archive.save("capture-result.json", json.dumps({"passed": passed,
                          "postCleanupOriginalGuardPassed": passed, "nativeSHA256": receiver.digest(self.native)}).encode())

    def test_import_has_no_studio_dependency(self):
        self.assertNotIn("sync_from_studio", receiver.__dict__)
        self.assertNotIn("StudioMcpClient", receiver.__dict__)

    def test_valid_multichunk_transfer_and_empty_luau_maps(self):
        metadata = self.upload()
        self.assertEqual(metadata["native"]["parts"], 2)
        self.assertEqual((self.archive.dest / "native.rbxm").read_bytes(), self.native)
        self.assertTrue(self.archive.finalized)

    def test_scope_and_mutation_contract_rejects_wrong_root_script_or_ref(self):
        for change in (lambda f: f["scopeNames"].__setitem__(0, "OtherRoot"),
                       lambda f: f["forest"].__setitem__("scriptCount", 1),
                       lambda f: f.__setitem__("noOriginalMutation", False),
                       lambda f: f.__setitem__("deletionApproved", True),
                       lambda f: f["references"]["externalReadable"].append({"property": "PrimaryPart"})):
            facts = self.facts()
            change(facts)
            with self.assertRaises(AssertionError):
                receiver.validate_facts(facts, {"native": {"sha256": receiver.digest(self.native), "bytes": len(self.native)}})

    def test_invalid_forest_graph_and_wrong_partition_are_rejected(self):
        for change in (lambda f: f["forest"]["nodes"][0]["children"].append(1),
                       lambda f: f["forest"]["nodes"][1].__setitem__("parent", 0),
                       lambda f: f["forest"]["nodes"][0]["children"].pop(),
                       lambda f: f["forest"]["nodes"][0].__setitem__("archivable", False),
                       lambda f: f["forest"]["roots"][0].__setitem__("index", 98),
                       lambda f: f["forest"]["nodes"][0].__setitem__("name", "Wrong")):
            facts = self.facts()
            change(facts)
            with self.assertRaises(AssertionError):
                receiver.validate_facts(facts, {"native": {"sha256": receiver.digest(self.native), "bytes": len(self.native)}})

    def test_current_source_contract_rejects_raw_source_direct_consumers_and_duplicates(self):
        for change in (lambda f: f["sourceInventory"][0].__setitem__("source", "do not export this"),
                       lambda f: f["sourceInventory"][0]["directRetiredNameMatches"].append(receiver.NAMES[0]),
                       lambda f: f["sourceInventory"][1].__setitem__("path", "Fixture.Module0"),
                       lambda f: f["sourceInventory"][0].__setitem__("sourceSHA256", "bad")):
            facts = self.facts()
            change(facts)
            with self.assertRaises(AssertionError):
                receiver.validate_facts(facts, {"native": {"sha256": receiver.digest(self.native), "bytes": len(self.native)}})

    def test_scope_path_and_existing_archive_cannot_be_overwritten(self):
        for destination in (self.base.parent / "retired-authoring-archive-escape", self.base / "other-scope", self.archive.dest):
            with self.assertRaises(AssertionError):
                receiver.Archive(destination, "capture", 51, 2)

    def test_foreign_lease_bad_paths_and_oversized_parts_do_not_write(self):
        for path, raw, lease in (("/part/native/0", b"x", "other"), ("/part/native/../x", b"x", self.archive.capture_id),
                                 ("/part/native/256", b"x", self.archive.capture_id),
                                 ("/part/native/00", b"x", self.archive.capture_id),
                                 ("/part/native/0", b"x" * (receiver.PART_BYTES + 1), self.archive.capture_id)):
            with self.assertRaises(AssertionError):
                self.archive.post(path, raw, lease)
        self.assertEqual(list(self.archive.dest.iterdir()), [])

    def test_chunk_retry_is_idempotent_and_changed_retry_is_rejected(self):
        self.archive.post("/part/native/0", b"same", self.archive.capture_id)
        self.archive.post("/part/native/0", b"same", self.archive.capture_id)
        with self.assertRaises(AssertionError):
            self.archive.post("/part/native/0", b"changed", self.archive.capture_id)
        self.assertEqual((self.archive.dest / "native-part-0000.bin").read_bytes(), b"same")

    def test_missing_extra_corrupt_and_mis_sized_chunks_cannot_finalize(self):
        metadata = self.upload(finalize=False)
        bad = copy.deepcopy(metadata)
        bad["native"]["sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            self.archive.post("/finalize", json.dumps(bad).encode(), self.archive.capture_id)
        self.archive.post("/part/native/2", b"extra", self.archive.capture_id)
        with self.assertRaises(AssertionError):
            self.archive.post("/finalize", json.dumps(metadata).encode(), self.archive.capture_id)
        self.assertFalse((self.archive.dest / "native.rbxm").exists())

    def test_finalized_parts_and_receipts_are_immutable(self):
        self.upload()
        for path in ("/part/native/0", "/finalize"):
            with self.assertRaises(AssertionError):
                self.archive.post(path, b"new", self.archive.capture_id)
        with self.assertRaises(AssertionError):
            self.archive.save("native.rbxm", b"replacement")
        self.assertEqual((self.archive.dest / "native.rbxm").read_bytes(), self.native)

    def test_verify_requires_final_mcp_capture_not_transfer_only(self):
        self.upload()
        with self.assertRaises(AssertionError):
            receiver.Archive(self.archive.dest, "verify", 51, 2)
        self.final_capture(False)
        with self.assertRaises(AssertionError):
            receiver.Archive(self.archive.dest, "verify", 51, 2)

    def test_verify_checks_native_corruption_before_issuing_source(self):
        self.upload()
        self.final_capture()
        (self.archive.dest / "native.rbxm").write_bytes(b"corrupted offline fixture")
        with self.assertRaises(AssertionError):
            receiver.Archive(self.archive.dest, "verify", 51, 2)

    def test_reopen_receipt_cannot_claim_completion_or_mutate_original(self):
        self.upload()
        self.final_capture()
        verify = receiver.Archive(self.archive.dest, "verify", 51, 2)
        receipt = {"schema": "retired-authoring-native-reopen-v1", "passed": False, "stage": "precompletion",
                   "deletionApproved": False, "originalWrites": 0, "sourceWrites": 0, "modeSwitches": 0}
        for key, value in (("stage", "mcp-completion"), ("passed", True), ("originalWrites", 1), ("sourceWrites", 1)):
            bad = dict(receipt, **{key: value})
            with self.assertRaises(AssertionError):
                verify.post("/verify-receipt", json.dumps(bad).encode(), verify.capture_id)
        verify.post("/verify-receipt", json.dumps(receipt).encode(), verify.capture_id)
        self.assertFalse(json.loads((verify.dest / verify.receipt_name).read_bytes())["passed"])

    def test_explicit_native_request_targets_edit_and_exact_guid(self):
        calls = []
        archive = self.archive
        class FakeClient:
            def call(self, name, args):
                calls.append((name, args))
                return "Current Studio Mode: Edit"
            def _request(self, method, args, timeout):
                calls.append((method, args, timeout))
                # Exercise failing completion persistence without executing Luau.
                return {"result": {"content": [{"type": "text", "text": json.dumps({"passed": False})}]}}
        with self.assertRaises(AssertionError):
            receiver.execute(archive, FakeClient())
        self.assertEqual(calls[0], ("get_studio_state", {"studio_id": receiver.STUDIO_ID}))
        request = calls[1][1]
        self.assertEqual(request["name"], "execute_luau")
        self.assertEqual(request["arguments"]["datamodel_type"], "Edit")
        self.assertEqual(request["arguments"]["studio_id"], receiver.STUDIO_ID)
        self.assertIn('"expectedRootCount":51', request["arguments"]["code"])
        self.assertFalse(json.loads((archive.dest / "capture-result.json").read_bytes())["passed"])

    def test_play_rejection_makes_no_native_call_or_mode_switch(self):
        class PlayClient:
            def call(self, *_args): return "Current Studio Mode: Play"
            def _request(self, *_args, **_kwargs): raise RuntimeError("Unexpected native call")
        with self.assertRaisesRegex(AssertionError, "Edit unavailable"):
            receiver.execute(self.archive, PlayClient())
        self.assertEqual(list(self.archive.dest.iterdir()), [])

    def test_main_cleanup_continues_after_independent_cleanup_exceptions(self):
        events = []
        class FakeServer:
            def __init__(self, address, handler): events.append(("bind", address))
            def serve_forever(self): pass
            def shutdown(self):
                events.append("shutdown")
                raise RuntimeError("shutdown fixture")
            def server_close(self): events.append("close server")
        class FakeThread:
            def __init__(self, **_kwargs): pass
            def start(self): events.append("start")
            def join(self, timeout): events.append(("join", timeout))
        class FakeClient:
            def __init__(self, *_args): pass
            def initialize(self): events.append("initialize")
            def close(self):
                events.append("close client")
                raise RuntimeError("client close fixture")
        fake_import = types.SimpleNamespace(StudioMcpClient=FakeClient, find_mcp_batch=lambda: "fixture")
        arguments = ["capture", "--dest", str(self.base / "retired-authoring-archive-lifecycle"),
                     "--expected-root-count", "51", "--expected-source-count", "2", "--execute"]
        with patch.object(receiver.http.server, "ThreadingHTTPServer", FakeServer), \
             patch.object(receiver.threading, "Thread", FakeThread), \
             patch.dict(sys.modules, {"sync_from_studio": fake_import}), \
             patch.object(receiver, "execute", side_effect=RuntimeError("primary fixture")):
            with self.assertRaisesRegex(RuntimeError, "primary fixture") as caught:
                receiver.main(arguments)
        self.assertIn("close client", events)
        self.assertIn("shutdown", events)
        self.assertIn("close server", events)
        self.assertIn(("join", 5), events)
        self.assertEqual(len(caught.exception.__notes__), 2)

    def test_complete_current_verifier_suffix_ownership_and_cleanup_lifecycle(self):
        tool_dir = FILE.parent
        module = ("return function(A,ARCHIVE_CONFIG,shared,game,DateTime)\n"
                  "local nativeTypeof=typeof\nlocal typeof=function(v) "
                  "if type(v)=='table' and v.ClassName then return 'Instance' end return nativeTypeof(v) end\n") + (
            tool_dir / "retired_authoring_archive_verify.luau").read_text(encoding="utf-8") + "\nend\n"
        (self.base / "native_verify_fixture.luau").write_text(module, encoding="utf-8")
        fixture = self.base / "verifier_lifecycle.luau"
        fixture.write_text((tool_dir / "retired_authoring_archive_lifecycle_fixture.luau").read_text(encoding="utf-8"), encoding="utf-8")
        luau = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
        self.assertTrue(luau.is_file(), "Reviewed Luau runner is required for this contract")
        result = subprocess.run([str(luau), str(fixture)], cwd=self.base, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("lifecycle scenarios passed: 12", result.stdout)

    def test_current_common_epoch_provenance_is_bounded_private_and_fail_closed(self):
        tool_dir = FILE.parent
        module = "return function(game,shared,SecurityCapabilities,Enum,typeof,task)\n" + (
            tool_dir / "retired_authoring_archive_common.luau").read_text(encoding="utf-8") + "\nreturn A\nend\n"
        (self.base / "native_common_fixture.luau").write_text(module, encoding="utf-8")
        fixture = self.base / "diagnostics.luau"
        fixture.write_text((tool_dir / "retired_authoring_archive_diagnostics_fixture.luau").read_text(encoding="utf-8"), encoding="utf-8")
        luau = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
        result = subprocess.run([str(luau), str(fixture)], cwd=self.base, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("diagnostic scenarios passed: 6", result.stdout)

    def test_full_current_capture_uses_positive_five_roots_and_never_empty_probe(self):
        tool_dir = FILE.parent
        module = "return function(A,ARCHIVE_CONFIG,shared,game,DateTime)\n" + (
            tool_dir / "retired_authoring_archive_capture.luau").read_text(encoding="utf-8") + "\nend\n"
        (self.base / "native_capture_fixture.luau").write_text(module, encoding="utf-8")
        fixture = self.base / "capture.luau"
        fixture.write_text((tool_dir / "retired_authoring_archive_capture_fixture.luau").read_text(encoding="utf-8"), encoding="utf-8")
        luau = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
        result = subprocess.run([str(luau), str(fixture)], cwd=self.base, capture_output=True, text=True, timeout=15)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("positive-five-root scenario passed: 1", result.stdout)


if __name__ == "__main__":
    unittest.main()
