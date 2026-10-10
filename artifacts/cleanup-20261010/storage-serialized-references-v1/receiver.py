"""Root-owned loopback collector; import does not start HTTP or contact Studio."""
from pathlib import Path
import hashlib
import http.server
import importlib.util
import re
import secrets
import threading

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
ORIGINAL = HERE.with_name("storage-restoration-v1") / "receiver.py"
ORIGINAL_SHA = "4a70b5216d45321461aa9e0c482cefc6391b389ef92e2f905783a60d832267bc"
assert hashlib.sha256(ORIGINAL.read_bytes()).hexdigest() == ORIGINAL_SHA, "Immutable receiver helpers changed"
spec = importlib.util.spec_from_file_location("immutable_restoration_receiver_helpers", ORIGINAL)
helpers = importlib.util.module_from_spec(spec); spec.loader.exec_module(helpers)
strict_json, encode, sha = helpers.strict_json, helpers.encode, helpers.sha
PART_BYTES = 500000
MAX_BYTES = 32 * 1024 * 1024
SCHEMA = "retired-authoring-joint-serialized-references-v1"


class Session:
    def __init__(self, dest, capture_id, private_token):
        self.dest = Path(dest).resolve()
        assert not self.dest.exists() and self.dest.parent.is_dir(), "New owned output directory required"
        assert re.fullmatch(r"[0-9a-f]{32}", capture_id) and re.fullmatch(r"[0-9a-f]{64}", private_token)
        self.dest.mkdir()
        self.capture_id, self._token = capture_id, private_token
        self.parts, self.bytes, self.short_part, self.completion = [], 0, False, None
        self.closed = False
    def save(self, name, raw):
        assert re.fullmatch(r"[a-z0-9][a-z0-9_.-]*", name) and type(raw) is bytes
        with (self.dest / name).open("xb") as stream: stream.write(raw)
    def authenticate(self, capture_id, token):
        assert not self.closed and capture_id == self.capture_id and type(token) is str and secrets.compare_digest(token, self._token), "Capture authentication refused"
    def accept_part(self, index, raw):
        assert self.completion is None and type(index) is int and index == len(self.parts) and not self.short_part, "Part order/completion mismatch"
        assert type(raw) is bytes and 0 < len(raw) <= PART_BYTES and self.bytes + len(raw) <= MAX_BYTES
        self.save(f"references-part-{index:04d}.bin", raw)
        self.parts.append({"bytes": len(raw), "sha256": sha(raw)})
        self.bytes += len(raw); self.short_part = len(raw) < PART_BYTES
    def accept_completion(self, raw):
        assert self.completion is None and type(raw) is bytes and 0 < len(raw) <= 100000
        value = strict_json(raw)
        self.save("native-completion.received.json", raw)  # Original received claims, even when validation fails.
        assert value["schema"] == SCHEMA and value["stage"] == "mcp-completion" and type(value["passed"]) is bool
        assert value["captureId"] == self.capture_id
        if value["passed"]:
            for key in ("all213SourcesUnchanged", "rawEngineSerializationCaptured", "finalOriginalGuardPassed",
                        "postCleanupOriginalGuardPassed", "ownedLeaseReleased", "ownedLedgerReleased", "opaqueSlotsRemainUncertified"):
                assert value[key] is True, key
            for key in ("referenceAbsenceCertified", "deletionApproved", "nativeExecutedByAuthor"):
                assert value[key] is False, key
            helpers.zero_fields(value, ("originalWrites", "instancesCreated", "modeSwitches", "connectionsRetained"))
            helpers.integer_fields(value, {"weldConstraints": 109, "placeId": 131311258779917, "universeId": 10559217407})
            assert value["cleanupErrors"] == [] and type(value["inputRootCount"]) is int and 6 <= value["inputRootCount"] <= 115
            assert type(value["referenceBytes"]) is int and value["referenceBytes"] == self.bytes
            transfer = value["transfer"]
            assert type(transfer) is dict and type(transfer.get("parts")) is int and type(transfer.get("bytes")) is int
            assert transfer == {"parts": len(self.parts), "bytes": self.bytes, "sha256": value["referenceSHA256"]}
            raw_refs = b"".join((self.dest / f"references-part-{i:04d}.bin").read_bytes() for i in range(len(self.parts)))
            assert len(raw_refs) == self.bytes and sha(raw_refs) == value["referenceSHA256"]
            self.save("references.rbxm", raw_refs)
        self.completion = value
        self.save("native-completion.json", raw)
        self.save("capture-verdict.json", encode({"schema": "retired-authoring-raw-reference-capture-verdict-v1",
            "capturePassed": value["passed"], "referenceAbsenceCertified": False, "deletionApproved": False,
            "nativeCompletionSHA256": sha(raw), "limits": "Known native completion plus exact transport. Raw Ref semantics and nonserialized protected slots are separate gates."}))


def make_handler(session):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_): pass
        def do_POST(self):
            try:
                session.authenticate(self.headers.get("X-Archive-Capture"), self.headers.get("X-Reference-Token"))
                assert all(len(self.headers.get_all(name, [])) == 1 for name in ("X-Archive-Capture", "X-Reference-Token", "Content-Length"))
                match = re.fullmatch(r"/part/references/(0|[1-9][0-9]{0,2})", self.path)
                assert match, "Unknown endpoint"
                text = self.headers.get("Content-Length", "")
                assert re.fullmatch(r"[1-9][0-9]{0,5}", text) and not self.headers.get("Transfer-Encoding")
                count = int(text); assert count <= PART_BYTES
                self.connection.settimeout(30)
                raw = self.rfile.read(count); assert len(raw) == count, "Short HTTP body"
                session.accept_part(int(match[1]), raw)
                self.send_response(200); self.send_header("Content-Length", "5"); self.end_headers(); self.wfile.write(b"saved")
            except Exception:
                # Never put private headers/tokens or exception values in HTTP/logs.
                self.send_error(409, "Capture request refused")
        def do_GET(self): self.send_error(404, "No read/control endpoint")
    return Handler


class OwnedServer:
    """Start/stop only in the Root driver after explicit --apply coordination."""
    def __init__(self, session, port=18917):
        self.session = session
        self.server = http.server.HTTPServer(("127.0.0.1", port), make_handler(session))
        self.thread = threading.Thread(target=self.server.serve_forever, kwargs={"poll_interval": 0.2}, daemon=True)
        self.started = False
    def start(self):
        assert not self.started
        self.thread.start(); self.started = True
    def stop_after_known_completion(self):
        if self.started:
            self.server.shutdown(); self.thread.join(timeout=10)
            assert not self.thread.is_alive(), "Owned receiver thread retained"
        self.server.server_close(); self.session.closed = True
