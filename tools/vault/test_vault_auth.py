"""Offline T12 contracts using actual modules, synthetic files, and fake HTTP."""

import argparse
import ast
import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import sys
import tempfile
import types
import unittest
from unittest.mock import patch
import urllib.request


TOOL_DIR = Path(__file__).resolve().parent
SOURCES = tuple(TOOL_DIR / name for name in (
    "vault_auth.py", "build_vault.py", "build_systems.py", "fix_folders.py",
    "test_vault_auth.py",
))
ENV_NAME = "MONGOTV_OBSIDIAN_MCP_TOKEN"
FAKE_TOKEN = "offline-fixture-bearer-canary"
OVERRIDE_TOKEN = "offline-fixture-override-canary"


def load_module(name, *, repo=None):
    """Execute the whole module; only redirect build_vault's REPO to test files."""
    path = TOOL_DIR / f"{name}.py"
    tree = ast.parse(path.read_text(encoding="utf-8-sig"), filename=str(path))
    if repo is not None:
        assignments = [node for node in tree.body if isinstance(node, ast.Assign)
                       and any(isinstance(target, ast.Name) and target.id == "REPO"
                               for target in node.targets)]
        if len(assignments) != 1 or name != "build_vault":
            raise AssertionError("Unexpected test repo boundary")
        assignments[0].value = ast.Call(
            func=ast.Name(id="Path", ctx=ast.Load()),
            args=[ast.Constant(value=str(repo))], keywords=[],
        )
    module = types.ModuleType(name)
    module.__file__ = str(path)
    sys.modules[name] = module
    exec(compile(ast.fix_missing_locations(tree), str(path), "exec"), module.__dict__)
    return module


class FakeResponse:
    def __init__(self, payload):
        self.payload = payload

    def __enter__(self):
        return self

    def __exit__(self, *_args):
        return False

    def read(self):
        return json.dumps(self.payload).encode("utf-8")


def result(text="fixture-result"):
    return {"result": {"content": [{"type": "text", "text": text}]}}


class VaultAuthContracts(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="mongotv-vault-auth-")
        self.addCleanup(self.temp.cleanup)
        self.repo = Path(self.temp.name)
        (self.repo / "assets").mkdir()
        (self.repo / "tools/vault").mkdir(parents=True)
        manifest = {
            "items": [], "counts": {"scripts": 0, "remoteEvents": 0, "total": 0},
            "studio": {"name": "offline-fixture", "id": "131311258779917"},
            "formatVersion": 1, "source": "offline-fixture",
            "finalNewlineContract": "offline-fixture",
            "extraMirroredFilesNotInStudio": [],
        }
        (self.repo / "studio-sync-manifest.json").write_text(
            json.dumps(manifest), encoding="utf-8",
        )
        for source in SOURCES[:3]:
            (self.repo / "tools/vault" / source.name).write_bytes(source.read_bytes())
        self.addCleanup(patch.stopall)
        patch.dict(os.environ, {}, clear=True).start()
        saved_modules = {name: sys.modules.get(name) for name in
                         ("vault_auth", "build_vault", "build_systems", "fix_folders")}

        def restore_modules():
            for name, previous in saved_modules.items():
                if previous is None:
                    sys.modules.pop(name, None)
                else:
                    sys.modules[name] = previous

        self.addCleanup(restore_modules)
        self.http = patch.object(urllib.request, "urlopen",
                                 side_effect=AssertionError("Real HTTP forbidden")).start()
        with patch.object(Path, "read_text", side_effect=AssertionError("Eager config read")):
            # Compile without a file read while protecting the entire import body.
            path = TOOL_DIR / "vault_auth.py"
            self.auth = types.ModuleType("vault_auth")
            self.auth.__file__ = str(path)
            sys.modules["vault_auth"] = self.auth
            exec(compile(path.read_bytes(), str(path), "exec"), self.auth.__dict__)
        self.config = self.repo / "Backrooms Stay Quiet/.obsidian/plugins/mcp-tools-istefox/data.json"
        self.auth.CONFIG_PATH = self.config

    def write_config(self, value, *, raw=False):
        self.config.parent.mkdir(parents=True, exist_ok=True)
        self.config.write_text(value if raw else json.dumps(value), encoding="utf-8")

    def valid_config(self, token=FAKE_TOKEN):
        self.write_config({
            "mcpTransport": {"bearerToken": token, "livePort": 27200},
            "mcpClientConfig": {"codexDiscovery": {"accessToken": "different-broker-canary"}},
        })

    def builders(self):
        with patch.object(Path, "write_text", side_effect=AssertionError("Import wrote files")), \
             patch.object(Path, "write_bytes", side_effect=AssertionError("Import wrote files")), \
             patch.object(Path, "mkdir", side_effect=AssertionError("Import created folders")), \
             patch.object(self.auth, "get_token", side_effect=AssertionError("Import requested token")):
            vault = load_module("build_vault", repo=self.repo)
            systems = load_module("build_systems")
            folders = load_module("fix_folders")
        # Imports bound the guarded function; use the actual resolver for calls.
        vault.get_token = systems.get_token = self.auth.get_token
        self.assertIs(folders.b, vault)
        self.assertTrue(vault.notes)
        self.assertTrue(systems.N)
        self.assertTrue(folders.notes)
        self.http.assert_not_called()
        self.assertFalse(self.config.exists())
        return vault, systems, folders

    def assert_request(self, request, timeout, *, rpc_id, expected_timeout, token=FAKE_TOKEN):
        self.assertEqual(request.full_url, "http://127.0.0.1:27200/mcp")
        self.assertEqual(request.get_method(), "POST")
        self.assertEqual(request.get_header("Authorization"), "Bearer " + token)
        self.assertEqual(request.get_header("Content-type"), "application/json")
        self.assertEqual(request.get_header("Accept"), "application/json, text/event-stream")
        self.assertEqual(timeout, expected_timeout)
        self.assertEqual(json.loads(request.data), {
            "jsonrpc": "2.0", "id": rpc_id, "method": "tools/call",
            "params": {"name": "fixture_tool", "arguments": {"unicode": "\u00e6"}},
        })

    def test_imports_are_config_and_write_free(self):
        self.builders()

    def test_existing_plugin_credential_and_refresh(self):
        self.valid_config()
        self.assertEqual(self.auth.get_token(), FAKE_TOKEN)
        self.valid_config(OVERRIDE_TOKEN)
        self.assertEqual(self.auth.get_token(), OVERRIDE_TOKEN)
        self.http.assert_not_called()

    def test_override_precedes_missing_and_invalid_config(self):
        os.environ[ENV_NAME] = OVERRIDE_TOKEN
        with patch.object(Path, "read_text", side_effect=AssertionError("Override read config")):
            self.assertEqual(self.auth.get_token(), OVERRIDE_TOKEN)
        self.write_config("invalid-json-canary", raw=True)
        self.assertEqual(self.auth.get_token(), OVERRIDE_TOKEN)

    def test_explicit_blank_override_is_rejected(self):
        self.valid_config()
        for value in ("", " \t\n"):
            with self.subTest(value=repr(value)):
                os.environ[ENV_NAME] = value
                with self.assertRaisesRegex(RuntimeError, "must be nonempty"):
                    self.auth.get_token()

    def test_missing_and_malformed_config_fail_without_leaks(self):
        for raw in (None, "invalid-json-canary", '{"mcpTransport":{"bearerToken":"private-error-canary",'):
            with self.subTest(case="missing" if raw is None else "invalid"):
                if raw is not None:
                    self.write_config(raw, raw=True)
                with self.assertRaisesRegex(RuntimeError, "Cannot read Obsidian") as caught:
                    self.auth.get_token()
                self.assertNotIn("private-error-canary", str(caught.exception))
                self.assertNotIn("invalid-json-canary", str(caught.exception))
                self.assertTrue(caught.exception.__suppress_context__)
        self.http.assert_not_called()

    def test_invalid_json_shapes_and_tokens(self):
        cases = [[], None, {}, {"mcpTransport": []}, {"mcpTransport": {}},
                 {"mcpClientConfig": {"codexDiscovery": {"accessToken": "private-error-canary"}}}]
        cases += [{"mcpTransport": {"bearerToken": token}}
                  for token in (None, False, 0, [], {}, "", " \t\n")]
        for number, config in enumerate(cases):
            with self.subTest(shape=number):
                self.write_config(config)
                with self.assertRaisesRegex(RuntimeError, "bearerToken must be nonempty") as caught:
                    self.auth.get_token()
                self.assertNotIn("private-error-canary", str(caught.exception))
        self.http.assert_not_called()

    def test_io_and_encoding_errors_are_bounded(self):
        for error in (PermissionError("private-error-canary"), UnicodeError("private-error-canary")):
            with self.subTest(kind=type(error).__name__), \
                 patch.object(Path, "read_text", side_effect=error):
                with self.assertRaises(RuntimeError) as caught:
                    self.auth.get_token()
                self.assertNotIn("private-error-canary", str(caught.exception))
                self.assertTrue(caught.exception.__suppress_context__)

    def test_bom_config(self):
        self.config.parent.mkdir(parents=True)
        self.config.write_bytes(b"\xef\xbb\xbf" + json.dumps({
            "mcpTransport": {"bearerToken": FAKE_TOKEN},
        }).encode())
        self.assertEqual(self.auth.get_token(), FAKE_TOKEN)

    def test_both_actual_requests_keep_contracts_and_refresh(self):
        vault, systems, _ = self.builders()
        self.valid_config()
        self.http.side_effect = lambda request, timeout: FakeResponse(result())
        for module, counter, timeout in ((vault, 101, 300), (systems, 501, 120)):
            with self.subTest(module=module.__name__):
                self.assertEqual(module.mcp("fixture_tool", {"unicode": "\u00e6"}), "fixture-result")
                request = self.http.call_args.args[0]
                self.assert_request(request, self.http.call_args.kwargs["timeout"],
                                    rpc_id=counter, expected_timeout=timeout)
                os.environ[ENV_NAME] = OVERRIDE_TOKEN
                self.assertEqual(module.mcp("fixture_tool", {"unicode": "\u00e6"}), "fixture-result")
                self.assert_request(self.http.call_args.args[0], self.http.call_args.kwargs["timeout"],
                                    rpc_id=counter + 1, expected_timeout=timeout, token=OVERRIDE_TOKEN)
                del os.environ[ENV_NAME]

    def test_missing_config_blocks_both_before_http_or_sleep(self):
        vault, systems, _ = self.builders()
        with patch.object(vault.time, "sleep", side_effect=AssertionError("Auth error slept")) as sleep:
            for module in (vault, systems):
                with self.subTest(module=module.__name__), self.assertRaises(RuntimeError):
                    module.mcp("fixture_tool", {})
            sleep.assert_not_called()
        self.http.assert_not_called()

    def test_unsafe_header_credentials_fail_without_leaks_or_retries(self):
        vault, systems, _ = self.builders()
        unsafe_values = ["private-header-canary" + character + "suffix"
                         for character in ("\r", "\n", "\t", "\x00", "\x7f", "\u00e6", "\u0100")]
        with patch.object(vault.time, "sleep", side_effect=AssertionError("Header error slept")) as sleep:
            for origin in ("config", "environment"):
                for token in unsafe_values:
                    self.valid_config(token if origin == "config" else FAKE_TOKEN)
                    if origin == "environment":
                        os.environ[ENV_NAME] = token
                    else:
                        os.environ.pop(ENV_NAME, None)
                    for module in (vault, systems):
                        with self.subTest(origin=origin, module=module.__name__), \
                             self.assertRaisesRegex(RuntimeError, "unsupported HTTP header characters") as caught:
                            module.mcp("fixture_tool", {})
                        self.assertNotIn("private-header-canary", str(caught.exception))
                        self.assertNotIn(token, str(caught.exception))
            sleep.assert_not_called()
        self.http.assert_not_called()

    def test_vault_transport_retry_success(self):
        vault, _, _ = self.builders()
        self.valid_config()
        self.http.side_effect = [OSError("fixture-1"), OSError("fixture-2"), FakeResponse(result())]
        with patch.object(vault.time, "sleep") as sleep:
            self.assertEqual(vault.mcp("fixture_tool", {"unicode": "\u00e6"}), "fixture-result")
            self.assertEqual([call.args for call in sleep.call_args_list], [(1,), (2,)])
        self.assertEqual(self.http.call_count, 3)
        self.assertEqual([json.loads(call.args[0].data)["id"] for call in self.http.call_args_list], [101, 102, 103])
        self.assertEqual([call.kwargs["timeout"] for call in self.http.call_args_list], [300] * 3)

    def test_vault_error_retries_preserve_final_exception(self):
        vault, _, _ = self.builders()
        self.valid_config()
        final_error = OSError("final-fixture-error")
        self.http.side_effect = [FakeResponse({"error": {"code": -1}}),
                                 FakeResponse({"result": {"isError": True, "content": [{"text": "tool-fixture-error"}]}}),
                                 final_error]
        with patch.object(vault.time, "sleep") as sleep:
            with self.assertRaises(OSError) as caught:
                vault.mcp("fixture_tool", {})
            self.assertIs(caught.exception, final_error)
            self.assertEqual([call.args for call in sleep.call_args_list], [(1,), (2,), (3,)])
        self.assertEqual(self.http.call_count, 3)

    def test_systems_errors_are_single_request(self):
        _, systems, _ = self.builders()
        self.valid_config()
        for payload, expected in (({"error": "rpc-fixture-error"}, "rpc-fixture-error"),
                                  ({"result": {"isError": True, "content": [{"text": "tool-fixture-error"}]}}, "tool-fixture-error")):
            with self.subTest(expected=expected):
                self.http.reset_mock()
                self.http.side_effect = lambda request, timeout: FakeResponse(payload)
                with self.assertRaisesRegex(RuntimeError, expected):
                    systems.mcp("fixture_tool", {})
                self.assertEqual(self.http.call_count, 1)
                self.assertEqual(self.http.call_args.kwargs["timeout"], 120)
        error = OSError("transport-fixture-error")
        self.http.side_effect = error
        with self.assertRaises(OSError) as caught:
            systems.mcp("fixture_tool", {})
        self.assertIs(caught.exception, error)

    def test_fix_folders_uses_actual_shared_request(self):
        vault, _, folders = self.builders()
        self.valid_config()
        self.http.side_effect = lambda request, timeout: FakeResponse(result('{"files":[]}'))
        self.assertEqual(json.loads(folders.b.mcp("list_vault_files", {"limit": 1000})), {"files": []})
        self.assertEqual(json.loads(self.http.call_args.args[0].data)["params"], {
            "name": "list_vault_files", "arguments": {"limit": 1000},
        })
        self.assertEqual(self.http.call_args.kwargs["timeout"], 300)
        self.assertIs(folders.b, vault)

    def test_actual_dry_branch_exits_before_side_effects(self):
        vault, _, _ = self.builders()
        tree = ast.parse((TOOL_DIR / "build_vault.py").read_text(encoding="utf-8"))
        entries = [node for node in tree.body if isinstance(node, ast.If)
                   and ast.unparse(node.test) == "__name__ == '__main__'"]
        self.assertEqual(len(entries), 1)
        branch = ast.Module(body=entries[0].body, type_ignores=[])
        capture = io.StringIO()
        with patch.object(sys, "argv", ["build_vault.py", "--dry"]), \
             patch.object(vault, "get_token", side_effect=AssertionError("Dry requested token")), \
             patch.object(vault, "copy_media", side_effect=AssertionError("Dry copied media")), \
             patch.object(vault, "push", side_effect=AssertionError("Dry pushed notes")), \
             patch.object(vault, "sweep_stale", side_effect=AssertionError("Dry deleted notes")), \
             contextlib.redirect_stdout(capture):
            with self.assertRaises(SystemExit) as caught:
                exec(compile(branch, "actual-isolated-dry-branch", "exec"), vault.__dict__)
        self.assertEqual(caught.exception.code, 0)
        self.assertIn("noter:", capture.getvalue())
        self.assertFalse(self.config.exists())
        self.http.assert_not_called()

    def test_generated_tool_notes_do_not_embed_runtime_credentials(self):
        vault, _, _ = self.builders()
        self.valid_config()
        os.environ[ENV_NAME] = OVERRIDE_TOKEN
        self.assertEqual(vault.get_token(), OVERRIDE_TOKEN)
        notes = "\n".join(vault.notes.values())
        self.assertNotIn(FAKE_TOKEN, notes)
        self.assertNotIn(OVERRIDE_TOKEN, notes)
        self.assertNotIn("different-broker-canary", notes)
        self.assertTrue(any(path.endswith("vault_auth.py.md") for path in vault.notes))

    def test_no_builder_token_assignment_or_reference(self):
        for filename in ("build_vault.py", "build_systems.py"):
            with self.subTest(file=filename):
                tree = ast.parse((TOOL_DIR / filename).read_text(encoding="utf-8"))
                self.assertFalse(any(isinstance(node, ast.Name) and node.id == "TOKEN"
                                     for node in ast.walk(tree)))
                imports = [node for node in tree.body if isinstance(node, ast.ImportFrom)
                           and node.module == "vault_auth"]
                self.assertEqual([[alias.name for alias in node.names] for node in imports], [["get_token"]])


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    if args.receipt is not None and args.receipt.exists():
        parser.error("Receipt already exists; refusing to overwrite evidence")
    before = {path.name: path.read_bytes() for path in SOURCES}
    suite = unittest.defaultTestLoader.loadTestsFromTestCase(VaultAuthContracts)
    names = [test.id().rsplit(".", 1)[-1] for test in suite]
    capture = io.StringIO()
    execution = unittest.TextTestRunner(stream=capture, verbosity=1).run(suite)
    unchanged = all(path.read_bytes() == before[path.name] for path in SOURCES)
    receipt = {
        "schema": "vault-auth-offline-tests-v1", "passed": execution.wasSuccessful() and unchanged,
        "tests": execution.testsRun, "failures": len(execution.failures), "errors": len(execution.errors),
        "testCases": names, "sourcesUnchanged": unchanged,
        "scope": "Actual module imports and isolated dry branch; synthetic vault and fake HTTP only",
        "nativeOrObsidianCalls": 0,
        "sources": {name: {"sha256": hashlib.sha256(raw).hexdigest(),
                            "lfSha256": hashlib.sha256(raw.replace(b"\r\n", b"\n")).hexdigest()}
                    for name, raw in before.items()},
    }
    if not receipt["passed"]:
        sys.stderr.write(capture.getvalue())
    if args.receipt is not None:
        args.receipt.parent.mkdir(parents=True, exist_ok=True)
        with args.receipt.open("x", encoding="utf-8", newline="\n") as stream:
            json.dump(receipt, stream, indent=2)
            stream.write("\n")
    print(json.dumps(receipt))
    return 0 if receipt["passed"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
