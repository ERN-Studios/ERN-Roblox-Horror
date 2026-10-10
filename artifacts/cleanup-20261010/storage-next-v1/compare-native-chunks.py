"""Read pinned native RBXM chunks exactly. Never transforms or rewrites archives."""
from pathlib import Path
import hashlib
import json
import struct
import lz4.block

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
INPUTS = {
    "original": ("artifacts/cleanup-serverstorage-20261009/external-storage-archive-v1/native.rbxm", "139a76d70022770ac30b0a4e9cfaeaea967668955ab0930666de0d3ab1f23dca"),
    "roundtrip": ("artifacts/cleanup-serverstorage-20261009/external-storage-reopen-v1/roundtrip.rbxm", "dbfb34d6dc742c50c4b743fd7a5fc0e374599f3b8c81ea1e8f5d6baa455eb121"),
}

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def text(raw, pos):
    size = struct.unpack_from("<I", raw, pos)[0]
    end = pos + 4 + size
    assert end <= len(raw)
    return raw[pos + 4:end].decode("utf-8"), end

def chunks(key):
    path, pinned = INPUTS[key]
    raw = (ROOT / path).read_bytes()
    assert len(raw) == 2739764 and sha(raw) == pinned
    assert raw[:14] == b"<roblox!\x89\xff\r\n\x1a\n"
    assert struct.unpack_from("<H", raw, 14)[0] == 0
    pos, result, classes = 32, [], {}
    while pos < len(raw):
        header = raw[pos:pos + 16]
        assert len(header) == 16
        kind, packed, unpacked, reserved = struct.unpack("<4sIII", header)
        assert reserved == 0 and unpacked <= 100_000_000
        start, end = pos + 16, pos + 16 + (packed or unpacked)
        assert end <= len(raw)
        body = raw[start:end]
        content = lz4.block.decompress(body, uncompressed_size=unpacked) if packed else body
        assert len(content) == unpacked
        row = {"index": len(result), "kind": kind.decode("ascii").rstrip("\x00"), "offset": pos,
            "compressedBytes": packed, "uncompressedBytes": unpacked, "rawSHA256": sha(header + body),
            "contentSHA256": sha(content), "content": content}
        if kind == b"INST":
            class_id = struct.unpack_from("<I", content)[0]
            class_name, _ = text(content, 4)
            assert class_id not in classes
            classes[class_id] = class_name
            row.update(classId=class_id, className=class_name)
        elif kind == b"PROP":
            class_id = struct.unpack_from("<I", content)[0]
            property_name, cursor = text(content, 4)
            row.update(classId=class_id, property=property_name, propertyTypeByte=content[cursor])
        result.append(row)
        pos = end
        if kind == b"END\x00":
            assert pos == len(raw)
    for row in result:
        if row["kind"] == "PROP":
            row["className"] = classes[row["classId"]]
    return raw[:32], result

head_a, a = chunks("original")
head_b, b = chunks("roundtrip")
assert head_a == head_b and len(a) == len(b)
differences = []
raw_differences = 0
for aa, bb in zip(a, b, strict=True):
    assert {k: v for k, v in aa.items() if k not in {"content", "contentSHA256", "rawSHA256"}} == {k: v for k, v in bb.items() if k not in {"content", "contentSHA256", "rawSHA256"}}, "Binary chunk layout differs"
    raw_differences += aa["rawSHA256"] != bb["rawSHA256"]
    if aa["content"] == bb["content"]:
        continue
    assert len(aa["content"]) == len(bb["content"])
    byte_deltas = [{"uncompressedOffset": i, "before": x, "after": y} for i, (x, y) in enumerate(zip(aa["content"], bb["content"], strict=True)) if x != y]
    differences.append({k: v for k, v in aa.items() if k != "content"} | {"afterContentSHA256": bb["contentSHA256"], "changedByteCount": len(byte_deltas), "changedBytes": byte_deltas})
report = {"schema": "s06-exact-native-chunk-diagnostic-v1", "nativeCalls": 0, "nativeWrites": 0,
    "restorationCertified": False, "normalizationApplied": False, "archiveHeaderByteExact": True,
    "binaryChunkCount": len(a), "rawChunkDifferenceCount": raw_differences, "contentChunkDifferenceCount": len(differences),
    "identicalContentChunks": len(a) - len(differences), "differences": differences,
    "inputs": {key: {"path": path, "bytes": 2739764, "sha256": digest} for key, (path, digest) in INPUTS.items()},
    "limits": "Exact historical RBXM byte/chunk comparison only. Runtime computed/nonserialized and ReflectionService-readable values are not recorded for owned copies. No live source, gameplay, recovery or deletion approval."}
target = OUT / "native-chunk-differences.json"
assert not target.exists()
with target.open("xb") as stream:
    stream.write((json.dumps(report, indent=2) + "\n").encode())
print(json.dumps({"chunks": len(a), "changedContentChunks": len(differences), "output": str(target)}))
