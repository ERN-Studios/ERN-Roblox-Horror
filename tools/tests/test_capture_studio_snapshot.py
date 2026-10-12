"""Offline capture/apply integration: frozen hashes, paths, and local races.

No Studio calls, native compilation, or gameplay certification.
Run: python -B -m unittest discover -s tools/tests -p test_capture_studio_snapshot.py
"""
import argparse
import copy
from contextlib import redirect_stdout
import hashlib
import io
import json
import os
from pathlib import Path
import re
import sys
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import zipfile

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import capture_studio_snapshot as tool


def source_row(segments, data, klass="Script"):
    canonical = tool.canonical_bytes(data.decode("utf-8"))
    props = {"Archivable": True, "LinkedSource": "", "SourceAssetId": -1}
    if klass in {"Script", "LocalScript"}:
        props.update(Enabled=True, Disabled=False, RunContext="Enum.RunContext.Server")
    return {"segments": segments, "path": ".".join(segments), "className": klass,
            "instanceId": "id:" + "/".join(segments), "parentId": "parent:" + "/".join(segments[:-1]),
            "properties": props, "attributes": {"Position": {"robloxType": "Vector3", "value": [1, 2, 3]}}, "tags": ["a", "z"],
            "sourceEditorMatches": True, "sourceBytes": len(data), "canonicalBytes": len(canonical), "sourceHash": tool.djb2(data),
            "rawSourceSHA256": hashlib.sha256(data).hexdigest(), "rawEditorSHA256": hashlib.sha256(data).hexdigest(),
            "sourceSHA256": hashlib.sha256(canonical).hexdigest()}


def native_empty_tables(value):
    """Match native canonical(): an empty Lua array serializes as {}."""
    if isinstance(value, list):
        return [native_empty_tables(v) for v in value] if value else {}
    if isinstance(value, dict):
        return {k: native_empty_tables(v) for k, v in value.items()}
    return value


class FakeStudio:
    def __init__(self, inventory, payloads, final_change=None, corrupt_chunk=False):
        self.inventory = inventory
        self.payloads = payloads
        self.final_change = final_change
        self.corrupt_chunk = corrupt_chunk
        self.enumerations = self.chunks = 0
        self.closed = False

    def initialize(self):
        pass

    def close(self):
        self.closed = True

    def call(self, name, args=None):
        args = args or {}
        if name == "list_roblox_studios":
            return json.dumps({"studios": [{"id": "fake", "name": tool.RELEASE_STUDIO_NAME}]})
        if name == "get_studio_state":
            return "- Current Studio Mode: Edit\n- Available DataModels: Edit"
        if name != "execute_luau" or args["datamodel_type"] != "Edit":
            raise AssertionError("Unexpected API; only read-only native Edit reads permitted")
        code = args["code"]
        if "-- snapshot-inventory" in code:
            self.enumerations += 1
            value = copy.deepcopy(self.inventory)
            if self.enumerations > 1 and self.final_change:
                self.final_change(value)
            data = json.dumps(native_empty_tables(value), sort_keys=True, ensure_ascii=False, separators=(",", ":")).encode("utf-8")
            first = int(re.search(r"-- snapshot-inventory-page first=(\d+)", code)[1])
            return json.dumps({"catalogBytes": len(data), "catalogSHA256": hashlib.sha256(data).hexdigest(), "catalogHash": tool.djb2(data),
                               "sourceCount": len(value["sources"]), "remoteCount": len(value["remotes"]), "first": first,
                               "hex": data[first - 1:first - 1 + tool.INVENTORY_CHUNK_BYTES].hex()})
        if "-- snapshot-chunk" in code:
            self.chunks += 1
            code = code.split("-- snapshot-chunk", 1)[1]
            segments = json.loads(re.search(r"local segments=(\{[^\n]+\})", code)[1].replace("{", "[").replace("}", "]"))
            first, last = map(int, re.search(r"local chunk=hexChunk\(text,(\d+),(\d+)\)", code).groups())
            data = self.payloads[tuple(segments)][first - 1:last]
            if self.corrupt_chunk:
                data = b"bad"
            return json.dumps(data.hex())
        raise AssertionError("Unknown native read")


class SnapshotTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="full-studio-export-")
        self.root = Path(self.temp.name) / "repo"
        self.root.mkdir()
        self.out = Path(self.temp.name) / "capture"
        self.args = argparse.Namespace(project_root=self.root, output=self.out, studio_name=tool.RELEASE_STUDIO_NAME, connect_timeout=1)
        self.data = ("-- ø😀\n" + "local n=1\n" * 6000).encode("utf-8")
        self.row = source_row(["ServerScriptService", "Sample"], self.data)
        self.remote = {"segments": ["ReplicatedStorage", "Event"], "path": "ReplicatedStorage.Event", "className": "RemoteEvent",
                       "instanceId": "remote", "parentId": "storage", "properties": {"Archivable": False}, "attributes": {}, "tags": []}
        self.inventory = {"placeId": tool.EXPECTED_PLACE_ID, "universeId": tool.EXPECTED_UNIVERSE_ID,
                          "sources": [self.row], "remotes": [self.remote]}
        self.path = self.root / tool.relative(self.row)
        self.path.parent.mkdir()
        self.path.write_bytes(b"-- local baseline\r\n")
        self.old = self.root / "ServerScriptService/Retired.Script.lua"
        self.old.write_bytes(b"-- old mirror\n")
        self.manifest = self.root / tool.MANIFEST
        self.manifest.write_text(json.dumps({"items": [{"file": self.old.relative_to(self.root).as_posix()}]}), encoding="utf-8")

    def tearDown(self):
        self.temp.cleanup()

    def capture(self, **kwargs):
        client = FakeStudio(copy.deepcopy(self.inventory), {tuple(self.row["segments"]): self.data}, **kwargs)
        with redirect_stdout(io.StringIO()):
            result = tool.capture(self.args, lambda: client, tracked=set())
        self.assertTrue(client.closed)
        return result, client

    def test_complete_capture_apply_and_recovery(self):
        snapshot, client = self.capture()
        self.assertEqual(client.enumerations, 2)
        self.assertGreater(client.chunks, 1)
        self.assertEqual(self.path.read_bytes(), b"-- local baseline\r\n")
        self.assertEqual(snapshot["sources"][0]["rawSourceSHA256"], hashlib.sha256(self.data).hexdigest())
        with redirect_stdout(io.StringIO()):
            manifest = tool.apply(self.args)
        self.assertEqual(self.path.read_bytes(), self.data)
        self.assertFalse(self.old.exists())
        row = manifest["items"][0]
        self.assertEqual(row["instanceId"], self.row["instanceId"])
        self.assertEqual(row["attributes"], self.row["attributes"])
        self.assertEqual(row["tags"], ["a", "z"])
        self.assertTrue(row["sourceEditorMatches"])
        self.assertFalse(manifest["items"][1]["properties"]["Archivable"])
        with zipfile.ZipFile(self.out / "before-mirror.zip") as archive:
            self.assertEqual(archive.read(tool.relative(self.row)), b"-- local baseline\r\n")
            self.assertEqual(archive.read("ServerScriptService/Retired.Script.lua"), b"-- old mirror\n")
        self.assertIn(tool.MANIFEST, json.loads((self.out / "stage-paths.json").read_text()))

    def test_native_change_never_completes_snapshot(self):
        client = FakeStudio(self.inventory, {tuple(self.row["segments"]): self.data}, final_change=lambda v: v["sources"][0].update(parentId="other"))
        with redirect_stdout(io.StringIO()), self.assertRaises(tool.StudioMcpError):
            tool.capture(self.args, lambda: client, tracked=set())
        self.assertTrue(client.closed)
        self.assertFalse((self.out / "snapshot.json").exists())
        self.assertEqual(self.path.read_bytes(), b"-- local baseline\r\n")

    def test_corrupt_chunk_never_completes_snapshot(self):
        with self.assertRaises(tool.StudioMcpError):
            self.capture(corrupt_chunk=True)
        self.assertFalse((self.out / "snapshot.json").exists())

    def test_local_change_aborts_before_any_write(self):
        self.capture()
        self.path.write_bytes(b"-- concurrent developer work\n")
        with self.assertRaises(tool.StudioMcpError):
            tool.apply(self.args)
        self.assertEqual(self.path.read_bytes(), b"-- concurrent developer work\n")
        self.assertTrue(self.old.exists())
        self.assertFalse((self.out / "before-mirror.zip").exists())

    def test_new_local_mirror_aborts_before_any_write(self):
        self.capture()
        added = self.root / "ServerScriptService/New.Script.lua"
        added.write_bytes(b"-- developer work\n")
        with self.assertRaises(tool.StudioMcpError):
            tool.apply(self.args)
        self.assertEqual(added.read_bytes(), b"-- developer work\n")
        self.assertTrue(self.old.exists())

    def test_checkpoint_race_is_rechecked(self):
        self.capture()
        original_close = zipfile.ZipFile.close
        mutated = False
        def close(archive):
            nonlocal mutated
            original_close(archive)
            if not mutated and archive.filename == str(self.out / "before-mirror.zip"):
                mutated = True
                self.path.write_bytes(b"-- concurrent work after checkpoint\n")
        with patch.object(zipfile.ZipFile, "close", close), self.assertRaises(tool.StudioMcpError):
            tool.apply(self.args)
        self.assertEqual(self.path.read_bytes(), b"-- concurrent work after checkpoint\n")
        self.assertTrue(self.old.exists())

    def test_source_reuse_requires_raw_native_sha(self):
        self.path.write_bytes(self.data.replace(b"\n", b"\r\n"))
        _, client = self.capture()
        self.assertGreater(client.chunks, 0)

    def test_hash_tampering_rejected(self):
        self.capture()
        snapshot = json.loads((self.out / "snapshot.json").read_text(encoding="utf-8"))
        snapshot["sources"][0]["sourceSHA256"] = "0" * 64
        tool.write_json(self.out / "snapshot.json", snapshot)
        with self.assertRaises(tool.StudioMcpError):
            tool.apply(self.args)

    def test_paths_and_collisions_rejected(self):
        for rel in ("../outside.lua", "/outside.lua", "C:/outside.lua", "ServerScriptService/CON.Script.lua", "ServerScriptService/name .", "ServerScriptService//x.lua"):
            with self.subTest(rel=rel), self.assertRaises(tool.StudioMcpError):
                tool.safe_path(self.root, rel)
        for segments in (["ServerScriptService", "sample"], ["serverscriptservice", "Other"]):
            value = copy.deepcopy(self.inventory)
            value["sources"].append(source_row(segments, b"return 1"))
            with self.subTest(segments=segments), self.assertRaises(tool.StudioMcpError):
                tool.validate_inventory(value)
        value = copy.deepcopy(self.inventory)
        value["sources"] = [source_row(["ServerScriptService", "A.B"], b"return 1"), source_row(["ServerScriptService", "A", "B"], b"return 2")]
        with self.assertRaises(tool.StudioMcpError):
            tool.validate_inventory(value)

    def test_metadata_and_editor_conflicts_rejected(self):
        for key, bad in (("sourceEditorMatches", False), ("rawEditorSHA256", "0" * 64), ("instanceId", "")):
            value = copy.deepcopy(self.inventory)
            value["sources"][0][key] = bad
            with self.subTest(key=key), self.assertRaises(tool.StudioMcpError):
                tool.validate_inventory(value)
        value = copy.deepcopy(self.inventory)
        value["sources"][0]["properties"]["Disabled"] = True
        with self.assertRaises(tool.StudioMcpError):
            tool.validate_inventory(value)

    def test_generated_native_code_has_only_read_protocol(self):
        code = tool.ENUMERATE + tool.chunk_code(self.row, 1)
        self.assertIn("game:GetDescendants()", code)
        self.assertIn("i%1000==0", code)
        self.assertIn("Enum.HashAlgorithm.Sha256", code)
        self.assertIn("GetEditorSource", code)
        for mutation in ("Instance.new", ":Clone(", ":Destroy(", "UpdateSourceAsync", "HttpEnabled=", "search_game_tree"):
            self.assertNotIn(mutation, code)

    def test_inventory_pages_cover_catalog_larger_than_mcp_response_cap(self):
        self.inventory["sources"][0]["attributes"]["LargeFixture"] = "a" * 120000
        _, client = self.capture()
        self.assertGreater(client.enumerations, 4)

    def test_inventory_comparison_preserves_attribute_types(self):
        self.assertFalse(tool.same({"attribute": True}, {"attribute": 1}))
        self.assertFalse(tool.same({"attribute": False}, {"attribute": 0}))
        self.assertTrue(tool.same({"x": True, "y": [1]}, {"y": [1], "x": True}))

    def test_native_empty_array_tables_normalized_by_fixed_schema(self):
        self.inventory["sources"][0]["tags"] = []
        snapshot, _ = self.capture()
        self.assertEqual(snapshot["sources"][0]["tags"], [])
        self.assertEqual(snapshot["remotes"][0]["tags"], [])
        self.assertEqual(snapshot["remotes"][0]["attributes"], {})
        empty = {"placeId": tool.EXPECTED_PLACE_ID, "universeId": tool.EXPECTED_UNIVERSE_ID, "sources": [], "remotes": []}
        client = FakeStudio(empty, {})
        studio = {"id": "fake"}
        self.assertEqual(tool.read_inventory(client, studio), empty)

    def test_actual_generated_luau_compiles(self):
        compiler = Path(os.environ.get("TEMP", "")) / "codex-luau-0.737/luau-compile.exe"
        if not compiler.is_file():
            self.skipTest("Pinned Luau 0.737 compiler is not installed")
        with tempfile.TemporaryDirectory(prefix="snapshot-luau-compile-") as directory:
            fixture = Path(directory) / "fixture.luau"
            for code in (tool.ENUMERATE, tool.chunk_code(self.row, 1)):
                fixture.write_text(code, encoding="utf-8")
                for optimization in ("-O0", "-O1"):
                    run = subprocess.run([str(compiler), "--binary", optimization, str(fixture)], capture_output=True, timeout=20)
                    self.assertEqual(run.returncode, 0, run.stderr.decode(errors="replace"))


if __name__ == "__main__":
    unittest.main()
