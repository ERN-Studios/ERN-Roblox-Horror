"""Actual receiver main()/Handler tests with no socket, subprocess or Studio calls."""
from __future__ import annotations

import argparse
from contextlib import ExitStack, redirect_stderr, redirect_stdout
import hashlib
import importlib.util
import io
import json
from pathlib import Path
import sys
import tempfile
import types
from unittest import mock

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
WRAPPER = HERE / "storage_record_archive.py"


def load_wrapper():
    # The real tool module is executed, but even an accidental import-time MCP
    # construction hits a forbidden stub instead of importing native connectors.
    stub = types.ModuleType("sync_from_studio")
    def forbidden(*_args, **_kwargs):
        raise AssertionError("Unmocked MCP boundary")
    stub.StudioMcpClient = stub.find_mcp_batch = stub.select_studio = forbidden
    stub.RELEASE_STUDIO_NAME = "BACKROOMS: STAY QUIET [CO-OP HORROR]"
    spec = importlib.util.spec_from_file_location("storage_receiver_under_test", WRAPPER)
    module = importlib.util.module_from_spec(spec)
    assert spec.loader is not None
    before_path = sys.path[:]
    with mock.patch.dict(sys.modules, {"sync_from_studio": stub}):
        try:
            spec.loader.exec_module(module)
        finally:
            sys.path[:] = before_path
    return module


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", type=Path, help="Optional NEW bounded JSON receipt")
    args = parser.parse_args()
    if args.receipt:
        assert not args.receipt.exists(), "Refusing existing test receipt"
    wrapper_before = WRAPPER.read_bytes()
    module = load_wrapper()
    checks, cases = 0, []

    def check(value, label):
        nonlocal checks
        checks += 1
        assert value, label

    def scenario(label, failures=(), *, finalize=True, play=False, primary=None,
                 expected=None, notes=(), invalid_dest=False, existing_dest=False):
        errors = {step: RuntimeError("fixture-" + step) for step in failures}
        if primary:
            errors[primary[0]] = primary[1]
        events, cleanup, posts, clients, servers, threads = [], [], [], [], [], []
        native, references = b"fixture native bytes", b"fixture joint reference bytes"
        digest = lambda value: hashlib.sha256(value).hexdigest()
        facts = {
            "schema": "folder-diagnostic-archive-v1", "placeId": 131311258779917,
            "universeId": 10559217407, "nativeSHA256": digest(native), "nativeBytes": len(native),
            "referencesSHA256": digest(references), "referencesBytes": len(references),
            "roots": [{"name": f"transport-fixture-{i}", "class": "Folder", "children": 0} for i in range(12)],
        }
        facts_bytes = json.dumps(facts).encode()
        transfer = {key: {"parts": 1, "bytes": len(value), "sha256": digest(value)}
                    for key, value in (("native", native), ("references", references), ("facts", facts_bytes))}
        transfer_bytes = json.dumps(transfer).encode()

        def step(name):
            events.append(name)
            if name in errors:
                raise errors[name]

        class FakeServer:
            def __init__(self, address, handler):
                step("server.create")
                check(address == ("127.0.0.1", 18913), label + ": wrong bind contract")
                self.handler = handler
                servers.append(self)
            def serve_forever(self):
                raise AssertionError("Fixture must never run an event loop")
            def shutdown(self):
                cleanup.append("server.shutdown")
                step("server.shutdown")
            def server_close(self):
                cleanup.append("server.server_close")
                step("server.server_close")

        class FakeThread:
            def __init__(self, target, daemon):
                step("thread.create")
                check(daemon and target == servers[0].serve_forever, label + ": thread ownership differs")
                self.started = False
                threads.append(self)
            def start(self):
                step("thread.start")
                self.started = True
            def join(self, timeout=None):
                cleanup.append("thread.join")
                check(self.started and timeout == 5, label + ": missing bounded owned-thread join")
                step("thread.join")

        def post(path, body):
            # Execute the actual nested Handler's POST/finalize logic in memory.
            handler = object.__new__(servers[0].handler)
            handler.path = path
            handler.headers = {"Content-Length": str(len(body))}
            handler.rfile = io.BytesIO(body)
            replies, rejected = [], []
            handler.answer = replies.append
            handler.send_error = lambda code, text: rejected.append((code, text))
            handler.do_POST()
            check(not rejected and replies == [b"saved"], label + ": receiver rejected fixture transfer")
            posts.append(path)

        class FakeClient:
            def __init__(self, batch):
                step("client.create")
                check(batch == "fixture-batch", label + ": wrong MCP batch")
                clients.append(self)
            def initialize(self):
                step("client.initialize")
            def call(self, name, payload):
                check(payload["studio_id"] == "fixture-studio", label + ": wrong explicit Studio id")
                if name == "get_studio_state":
                    step("client.state")
                    return "Current Studio Mode: Play" if play else "Current Studio Mode: Edit"
                check(name == "execute_luau" and payload["datamodel_type"] == "Edit", label + ": unexpected native operation")
                check(payload["code"] == (HERE / "capture_storage_records.luau").read_text(encoding="utf8"), label + ": wrong capture source")
                for key, value in (("native", native), ("references", references), ("facts", facts_bytes)):
                    post("/" + key + "/0", value)
                # Duplicate identical chunks are accepted by the real immutable receiver.
                post("/native/0", native)
                step("client.capture")
                if finalize:
                    post("/finalize", transfer_bytes)
                return "fixture native capture completed"
            def close(self):
                cleanup.append("client.close")
                step("client.close")

        def find_batch():
            step("find_mcp_batch")
            return "fixture-batch"
        def select(client, title, timeout):
            step("select_studio")
            check(client in clients and title == module.RELEASE_STUDIO_NAME and timeout == 15, label + ": selection contract differs")
            return {"id": "fixture-studio"}

        with tempfile.TemporaryDirectory(prefix="mongotv-receiver-lifecycle-") as owned:
            root = Path(owned)
            dest = root / "archive"
            if invalid_dest:
                dest = root.parent / (root.name + "-outside")
            if existing_dest:
                dest.mkdir(); (dest / "keep.bin").write_bytes(b"existing evidence")
            caught = None
            stdout, stderr = io.StringIO(), io.StringIO()
            with ExitStack() as stack:
                stack.enter_context(mock.patch.object(module, "ROOT", root))
                stack.enter_context(mock.patch.object(sys, "argv", [str(WRAPPER), "--dest", str(dest)]))
                stack.enter_context(mock.patch.object(module.http.server, "ThreadingHTTPServer", FakeServer))
                stack.enter_context(mock.patch.object(module.threading, "Thread", FakeThread))
                stack.enter_context(mock.patch.object(module, "StudioMcpClient", FakeClient))
                stack.enter_context(mock.patch.object(module, "find_mcp_batch", find_batch))
                stack.enter_context(mock.patch.object(module, "select_studio", select))
                stack.enter_context(redirect_stdout(stdout)); stack.enter_context(redirect_stderr(stderr))
                try:
                    module.main()
                except BaseException as error:
                    caught = error
            if expected in errors:
                check(caught is errors[expected], label + ": primary/first cleanup error was replaced")
            elif expected:
                check(isinstance(caught, AssertionError) and expected in str(caught), label + ": expected assertion missing")
            else:
                check(caught is None, label + ": unexpected exception")
            wanted = []
            if clients:
                wanted.append("client.close")
            started = bool(threads and threads[0].started)
            if servers and started:
                wanted.append("server.shutdown")
            if servers:
                wanted.append("server.server_close")
            if started:
                wanted.append("thread.join")
            check(cleanup == wanted, label + ": cleanup independence/order differs")
            if notes:
                note_text = "\n".join(getattr(caught, "__notes__", []))
                check(all("fixture-" + name in note_text for name in notes), label + ": cleanup notes lost")
            if invalid_dest:
                check(not dest.exists() and not events, label + ": invalid destination touched")
            elif existing_dest:
                check((dest / "keep.bin").read_bytes() == b"existing evidence" and not events, label + ": existing archive touched")
            elif "/native/0" in posts:
                check((dest / "native-part-0000.bin").read_bytes() == native, label + ": partial evidence lost")
                if "/finalize" in posts:
                    check((dest / "transfer-receipt.json").read_bytes() == transfer_bytes, label + ": transfer receipt differs")
                    check((dest / "native.rbxm").read_bytes() == native and (dest / "references.rbxm").read_bytes() == references,
                          label + ": assembled native bytes differ")
                    check((dest / "facts.json").read_bytes() == facts_bytes, label + ": facts differ")
                    check((dest / "capture-result.txt").read_bytes() == b"fixture native capture completed", label + ": capture result absent")
                else:
                    check(not (dest / "transfer-receipt.json").exists(), label + ": failure created final receipt")
            if play:
                check("client.capture" not in events and not posts, label + ": Play capture attempted")
            cases.append({"name": label, "passed": True})

    scenario("success creates exact receipt and cleans all owned resources")
    for boundary in ("find_mcp_batch", "client.create", "client.initialize", "select_studio", "client.state", "client.capture"):
        scenario(boundary + " failure", (boundary,), expected=boundary)
    scenario("Play mode refused without capture", play=True, expected="Edit unavailable")
    scenario("partial transfer retained without final receipt", finalize=False, expected="no deletion authorized")
    for cleanup in ("client.close", "server.shutdown", "server.server_close", "thread.join"):
        scenario(cleanup + " failure still attempts remaining cleanup", (cleanup,), expected=cleanup)
    cleanup_steps = ("client.close", "server.shutdown", "server.server_close", "thread.join")
    scenario("primary failure survives all cleanup failures", ("client.initialize", *cleanup_steps),
             expected="client.initialize", notes=cleanup_steps)
    scenario("first cleanup failure survives later failures", cleanup_steps,
             expected="client.close", notes=cleanup_steps[1:])
    for setup in ("server.create", "thread.create", "thread.start"):
        scenario(setup + " failure never shuts down or joins unstarted server thread", (setup,), expected=setup)
    scenario("thread start primary survives close failure", ("thread.start", "server.server_close"),
             expected="thread.start", notes=("server.server_close",))
    scenario("interrupt primary survives cleanup failure", ("client.close",),
             primary=("client.initialize", KeyboardInterrupt("fixture-interrupt")), expected="client.initialize", notes=("client.close",))
    scenario("outside-workspace destination rejected", invalid_dest=True, expected="remain in workspace")
    scenario("existing archive preserved", existing_dest=True, expected="Refuse archive overwrite")
    check(WRAPPER.read_bytes() == wrapper_before, "Wrapper source changed during fixture")
    report = {"schema": "storage-receiver-lifecycle-offline-tests-v1", "passed": True,
              "checks": checks, "cases": cases, "caseCount": len(cases),
              "wrapperSHA256": hashlib.sha256(wrapper_before).hexdigest(),
              "testSHA256": hashlib.sha256(Path(__file__).read_bytes()).hexdigest(),
              "noNetworkOrStudio": True,
              "limits": "Actual Python main/Handler with fake resource boundaries and transport bytes; not native serializer, gameplay or real thread/socket certification."}
    if args.receipt:
        with args.receipt.open("x", encoding="utf8", newline="\n") as stream:
            json.dump(report, stream, indent=2); stream.write("\n")
    print(json.dumps({key: report[key] for key in ("passed", "checks", "caseCount", "wrapperSHA256", "noNetworkOrStudio")}))


if __name__ == "__main__":
    main()
