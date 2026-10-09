"""S04 immutable five-root engine archive on loopback 18914; explicit native execution only."""
from __future__ import annotations

import argparse
import base64
from collections import Counter
import hashlib
import http.server
import json
from pathlib import Path
import re
import sys
import threading
import uuid

ROOT = Path(__file__).resolve().parents[2]
BASE = ROOT / "artifacts/cleanup-serverstorage-20261009"
PORT = 18914
STUDIO_ID = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
SCHEMA = "retired-authoring-native-archive-v1"
NAMES = (
    "LobbyReimaginedBlenderSource20261001", "LobbyReimaginedBlenderSource20261001R2",
    "LobbyReimaginedBlenderSource20261001R3", "LobbyReimaginedBlenderSource20261001R3B",
    "Level1BlenderKit",
)
ROOT_COUNTS = (97, 97, 104, 104, 1215)
CLASSES = {"Folder": 365, "StringValue": 244, "Model": 283,
           "Part": 51, "MeshPart": 498, "SurfaceAppearance": 176}
PART_BYTES = 500_000
MAX_BYTES = {"native": 64 * 1024 * 1024, "facts": 16 * 1024 * 1024}


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def valid_hash(value) -> bool:
    return isinstance(value, str) and re.fullmatch(r"[0-9a-f]{64}", value) is not None


def validate_facts(facts, transfers):
    assert facts["schema"] == SCHEMA
    assert facts["stage"] == "precompletion" and facts["passed"] is False
    assert (facts["placeId"], facts["universeId"]) == (131311258779917, 10559217407)
    assert tuple(facts["scopeNames"]) == NAMES
    assert facts["rootCount"] == 5 and facts["totalInstances"] == 1617
    assert facts["noOriginalMutation"] is True and facts["deletionApproved"] is False
    assert facts["nativeSHA256"] == transfers["native"]["sha256"]
    assert facts["nativeBytes"] == transfers["native"]["bytes"]
    forest = facts["forest"]
    assert forest["instanceCount"] == 1617 and forest["scriptCount"] == 0
    assert tuple(r["name"] for r in forest["roots"]) == NAMES
    assert tuple(r["instances"] for r in forest["roots"]) == ROOT_COUNTS
    assert all(r["class"] == "Folder" for r in forest["roots"])
    nodes = forest["nodes"]
    assert len(nodes) == 1617 and [n["id"] for n in nodes] == list(range(1, 1618))
    assert Counter(n["class"] for n in nodes) == Counter(CLASSES)
    root_ids = [r["index"] for r in forest["roots"]]
    assert len(set(root_ids)) == 5 and all(type(i) is int and 1 <= i <= 1617 for i in root_ids)
    visited = set()

    def walk(index, parent):
        assert index not in visited and 1 <= index <= 1617
        visited.add(index)
        node = nodes[index - 1]
        assert node["parent"] == parent and node["archivable"] is True
        # Roblox JSONEncode emits [] for an empty table, including an empty map.
        assert isinstance(node["properties"], dict) or node["properties"] == []
        assert isinstance(node["attributes"], dict) or node["attributes"] == []
        assert isinstance(node["tags"], list) and isinstance(node["children"], list)
        assert isinstance(node["name"], str)
        count = 1
        for child in node["children"]:
            assert type(child) is int
            count += walk(child, index)
        return count

    for index, name, count in zip(root_ids, NAMES, ROOT_COUNTS):
        assert nodes[index - 1]["name"] == name and nodes[index - 1]["class"] == "Folder"
        assert walk(index, 0) == count
    assert len(visited) == 1617
    sources = facts["sourceInventory"]
    assert len(sources) == facts["sourceCount"] and facts["sourceCount"] >= 1
    assert len({s["path"] for s in sources}) == len(sources)
    for row in sources:
        assert row["class"] in ("Script", "LocalScript", "ModuleScript")
        assert valid_hash(row["sourceSHA256"]) and type(row["bytes"]) is int and row["bytes"] >= 0
        assert not row["directRetiredNameMatches"] and "source" not in row
    assert not facts["references"]["externalReadable"]


class Archive:
    """A new capture directory, or strictly validated existing bytes for a new reopen receipt."""

    def __init__(self, destination, phase, expected_roots, expected_sources,
                 receipt_name="native-reopen-v1.json"):
        self.dest = Path(destination).resolve()
        assert self.dest.is_relative_to(BASE.resolve()), "Destination escapes the archive workspace"
        assert self.dest.name.startswith("retired-authoring-archive-"), "Explicit S04 destination required"
        assert phase in ("capture", "verify")
        assert type(expected_roots) is int and expected_roots >= 5
        assert type(expected_sources) is int and expected_sources >= 1
        assert re.fullmatch(r"native-reopen-[A-Za-z0-9_-]+\.json", receipt_name)
        self.phase = phase
        self.expected_roots = expected_roots
        self.expected_sources = expected_sources
        self.receipt_name = receipt_name
        self.lock = threading.RLock()
        self.finalized = False
        self.native = None
        if phase == "capture":
            assert not self.dest.exists(), "Refuse archive overwrite; use a new versioned directory"
            self.dest.mkdir(parents=True)
            self.capture_id = uuid.uuid4().hex
        else:
            assert self.dest.is_dir(), "Captured archive is absent"
            assert not (self.dest / receipt_name).exists(), "Refuse reopen evidence overwrite"
            transfer_raw = (self.dest / "transfer-receipt.json").read_bytes()
            transfers = json.loads(transfer_raw)
            self.native = (self.dest / "native.rbxm").read_bytes()
            facts_raw = (self.dest / "facts.json").read_bytes()
            assert len(self.native) == transfers["native"]["bytes"] and digest(self.native) == transfers["native"]["sha256"]
            assert len(facts_raw) == transfers["facts"]["bytes"] and digest(facts_raw) == transfers["facts"]["sha256"]
            facts = json.loads(facts_raw)
            validate_facts(facts, transfers)
            result_path = self.dest / "capture-result.json"
            assert result_path.exists(), "A successful final native capture result is required"
            result = json.loads(result_path.read_bytes())
            assert result["passed"] and result["postCleanupOriginalGuardPassed"]
            assert result["nativeSHA256"] == digest(self.native)
            self.capture_id = facts["captureId"]
            self.finalized = True

    def save(self, filename, raw):
        assert Path(filename).name == filename
        path = self.dest / filename
        with self.lock:
            if path.exists():
                assert path.read_bytes() == raw, "Immutable evidence differs"
            else:
                with path.open("xb") as stream:
                    stream.write(raw)

    def context(self):
        result = {"schema": SCHEMA, "phase": self.phase, "captureId": self.capture_id,
                  "names": list(NAMES), "expectedRootCount": self.expected_roots,
                  "expectedSourceCount": self.expected_sources, "port": PORT}
        if self.native is not None:
            result.update(nativeBytes=len(self.native), nativeSHA256=digest(self.native),
                          nativeParts=(len(self.native) + PART_BYTES - 1) // PART_BYTES)
        return result

    def post(self, path, raw, capture_id):
        assert capture_id == self.capture_id, "Foreign transfer lease"
        assert 0 < len(raw) <= PART_BYTES
        with self.lock:
            if self.phase == "verify":
                assert path == "/verify-receipt"
                receipt = json.loads(raw)
                assert receipt["schema"] == "retired-authoring-native-reopen-v1"
                assert receipt["deletionApproved"] is False and receipt["originalWrites"] == 0
                assert receipt["sourceWrites"] == 0 and receipt["modeSwitches"] == 0
                assert receipt["stage"] == "precompletion" and receipt["passed"] is False
                self.save(self.receipt_name, raw)
                return
            if path == "/finalize":
                assert not self.finalized, "Capture is already finalized"
                transfers = json.loads(raw)
                assert set(transfers) == {"native", "facts"}
                assembled = {}
                for kind, meta in transfers.items():
                    assert type(meta["parts"]) is int and 0 < meta["parts"] <= 256
                    assert type(meta["bytes"]) is int and 0 < meta["bytes"] <= MAX_BYTES[kind]
                    assert valid_hash(meta["sha256"])
                    expected_parts = (meta["bytes"] + PART_BYTES - 1) // PART_BYTES
                    assert meta["parts"] == expected_parts
                    assert len(list(self.dest.glob(f"{kind}-part-*.bin"))) == meta["parts"]
                    pieces = [(self.dest / f"{kind}-part-{i:04d}.bin").read_bytes() for i in range(meta["parts"])]
                    assert all(len(part) == PART_BYTES for part in pieces[:-1])
                    value = b"".join(pieces)
                    assert len(value) == meta["bytes"] and digest(value) == meta["sha256"]
                    assembled[kind] = value
                facts = json.loads(assembled["facts"])
                validate_facts(facts, transfers)
                assert facts["captureId"] == self.capture_id
                assert (facts["serverStorageRootCount"], facts["sourceCount"]) == (self.expected_roots, self.expected_sources)
                self.save("native.rbxm", assembled["native"])
                self.save("facts.json", assembled["facts"])
                self.save("transfer-receipt.json", raw)
                self.native = assembled["native"]
                self.finalized = True
                return
            assert not self.finalized, "No parts may be appended to finalized evidence"
            match = re.fullmatch(r"/part/(native|facts)/(0|[1-9][0-9]{0,2})", path)
            assert match and int(match[2]) < 256, "Unknown part path/index"
            self.save(f"{match[1]}-part-{int(match[2]):04d}.bin", raw)


def make_handler(archive):
    class Handler(http.server.BaseHTTPRequestHandler):
        def log_message(self, *_args):
            pass

        def answer(self, body):
            self.send_response(200)
            self.send_header("Content-Length", str(len(body)))
            self.end_headers()
            self.wfile.write(body)

        def do_GET(self):
            if self.path == "/context":
                return self.answer(json.dumps(archive.context()).encode())
            match = re.fullmatch(r"/native-b64/(0|[1-9][0-9]{0,2})", self.path)
            if match and archive.phase == "verify" and archive.native is not None:
                begin = int(match[1]) * PART_BYTES
                if begin < len(archive.native):
                    return self.answer(base64.b64encode(archive.native[begin:begin + PART_BYTES]))
            self.send_error(404, "Unknown S04 archive endpoint")

        def do_POST(self):
            try:
                length = int(self.headers.get("Content-Length", "0"))
                assert 0 < length <= PART_BYTES
                raw = self.rfile.read(length)
                assert len(raw) == length
                archive.post(self.path, raw, self.headers.get("X-Archive-Capture"))
                self.answer(b"saved")
            except (AssertionError, ValueError, KeyError, OSError, TypeError):
                self.send_error(409, "Archive contract rejected; evidence remains immutable")
    return Handler


def native_code(archive):
    tool_dir = Path(__file__).resolve().parent
    context = archive.context()
    config = {key: context[key] for key in ("captureId", "expectedRootCount", "expectedSourceCount")}
    prefix = "local ARCHIVE_CONFIG=game:GetService(\"HttpService\"):JSONDecode([==[" + json.dumps(config, separators=(",", ":")) + "]==])\n"
    suffix = "capture" if archive.phase == "capture" else "verify"
    return prefix + (tool_dir / "retired_authoring_archive_common.luau").read_text(encoding="utf-8") + "\n" + (tool_dir / f"retired_authoring_archive_{suffix}.luau").read_text(encoding="utf-8")


def execute(archive, client):
    state = client.call("get_studio_state", {"studio_id": STUDIO_ID})
    assert "Current Studio Mode: Edit" in state, "Edit unavailable; do not switch modes"
    response = client._request("tools/call", {"name": "execute_luau", "arguments": {
        "studio_id": STUDIO_ID, "datamodel_type": "Edit", "code": native_code(archive),
    }}, timeout=900)
    result = response.get("result", {})
    assert not result.get("isError"), "Native tool rejected archive invocation"
    text = "\n".join(block.get("text", "") for block in result.get("content", []) if block.get("type") == "text")
    receipt = json.loads(text)
    name = "capture-result.json" if archive.phase == "capture" else archive.receipt_name.replace(".json", "-result.json")
    archive.save(name, (json.dumps(receipt, indent=2) + "\n").encode())
    assert receipt["passed"], "Native archive/reopen port failed; preserve evidence and originals"
    if archive.phase == "capture":
        assert archive.finalized and receipt["postCleanupOriginalGuardPassed"]
    else:
        assert receipt["postReceiptOriginalGuardPassed"] and receipt["receiptTransferred"]
        assert receipt["stage"] == "mcp-completion" and receipt["testOwnedRootsRemaining"] == 0
    return receipt


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=("capture", "verify"))
    parser.add_argument("--dest", type=Path, required=True)
    parser.add_argument("--expected-root-count", type=int, required=True)
    parser.add_argument("--expected-source-count", type=int, required=True)
    parser.add_argument("--receipt-name", default="native-reopen-v1.json")
    parser.add_argument("--execute", action="store_true", help="Explicitly invoke reviewed native read/reopen code")
    args = parser.parse_args(argv)
    archive = Archive(args.dest, args.phase, args.expected_root_count, args.expected_source_count, args.receipt_name)
    server = thread = client = None
    started = False
    try:
        server = http.server.ThreadingHTTPServer(("127.0.0.1", PORT), make_handler(archive))
        if not args.execute:
            print(json.dumps({"ready": True, "context": archive.context(), "dest": str(archive.dest), "nativeExecuted": False}), flush=True)
            started = True
            server.serve_forever()
            return
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        started = True
        # No Studio imports, connection, builders or native operations on ordinary import.
        sys.path.insert(0, str(ROOT / "tools"))
        from sync_from_studio import StudioMcpClient, find_mcp_batch
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        receipt = execute(archive, client)
        print(json.dumps(receipt), flush=True)
    finally:
        primary = sys.exc_info()[1]
        operations = []
        if client is not None:
            operations.append(("client.close", client.close))
        if server is not None:
            # Same-thread serve-only interruption must not call shutdown and deadlock.
            if started and thread is not None:
                operations.append(("server.shutdown", server.shutdown))
            operations.append(("server.server_close", server.server_close))
        if thread is not None and started:
            operations.append(("thread.join", lambda: thread.join(timeout=5)))
        errors = []
        for label, operation in operations:
            try:
                operation()
            except BaseException as error:
                errors.append((label, error))
        if errors:
            chosen = primary if primary is not None else errors[0][1]
            for label, error in errors:
                chosen.add_note(f"Cleanup {label} failed: {error}")
            if primary is None:
                raise chosen


if __name__ == "__main__":
    main()
