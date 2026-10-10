"""Bounded raw RBXM reference decoder. No reflection renaming or DOM normalization.

Keep the original buffer. Every chunk and PROP payload retains an offset/hash;
only Name strings and actual Ref columns are decoded. Unknown payloads are opaque
evidence, never discarded, coerced to null, or accepted as a required Ref field.
"""
from collections import Counter
from pathlib import Path
import argparse
import hashlib
import json
import struct

MAX_BYTES = 32 * 1024 * 1024
MAX_DECODED = 128 * 1024 * 1024
MAX_INSTANCES = 10000
NAMES = ("LobbyReimaginedBlenderSource20261001", "LobbyReimaginedBlenderSource20261001R2",
         "LobbyReimaginedBlenderSource20261001R3", "LobbyReimaginedBlenderSource20261001R3B", "Level1BlenderKit")
COUNTS = (97, 97, 104, 104, 1215)
CLASSES = {"Folder": 365, "StringValue": 244, "Model": 283, "Part": 51, "MeshPart": 498, "SurfaceAppearance": 176}
sha = lambda raw: hashlib.sha256(raw).hexdigest()


class Cursor:
    def __init__(self, raw): self.raw, self.at = raw, 0
    def take(self, count):
        assert type(count) is int and 0 <= count <= len(self.raw) - self.at, "Truncated binary value"
        value = self.raw[self.at:self.at + count]; self.at += count; return value
    def u8(self): return self.take(1)[0]
    def u32(self): return struct.unpack("<I", self.take(4))[0]
    def string(self):
        count = self.u32(); assert count <= MAX_BYTES, "String bound exceeded"; return self.take(count)
    def done(self): assert self.at == len(self.raw), "Unexpected trailing decoded bytes"


def refs(cursor, count):
    assert 0 <= count <= MAX_INSTANCES, "Referent count bound"
    raw = cursor.take(4 * count)
    result, prior = [], 0
    for index in range(count):
        unsigned = int.from_bytes(bytes(raw[index + lane * count] for lane in range(4)), "big")
        delta = (unsigned >> 1) ^ -(unsigned & 1)
        prior += delta
        assert -(2**31) <= prior < 2**31, "Referent accumulation overflow"
        result.append(prior)
    return result


def parse(raw):
    assert type(raw) is bytes and 32 <= len(raw) <= MAX_BYTES, "Raw size bound"
    cursor = Cursor(raw)
    assert cursor.take(14) == b"<roblox!\x89\xff\r\n\x1a\n", "Wrong native binary signature"
    assert cursor.take(2) == b"\0\0", "Unsupported native version"
    types, total = cursor.u32(), cursor.u32()
    assert 0 < types <= 1000 and 0 < total <= MAX_INSTANCES and cursor.take(8) == b"\0" * 8, "Header bounds/reserved"
    chunks, classes, nodes, properties, parents = [], {}, {}, {}, {}
    decoded_bytes, ended = 0, False
    while cursor.at < len(raw):
        start = cursor.at
        tag = cursor.take(4); compressed, size, reserved = cursor.u32(), cursor.u32(), cursor.u32()
        assert reserved == 0 and 0 <= size <= MAX_DECODED and compressed <= MAX_BYTES, "Chunk bounds/reserved"
        assert decoded_bytes + size <= MAX_DECODED and len(chunks) < 5000, "Pre-decompression decoded/chunk budget"
        stored = cursor.take(compressed or size)
        if compressed:
            assert not stored.startswith(b"\x28\xb5\x2f\xfd"), "Zstd is unsupported here; preserve raw and remain pending"
            import lz4.block
            payload = lz4.block.decompress(stored, uncompressed_size=size)
        else: payload = stored
        assert len(payload) == size, "Decompressed chunk size differs"
        decoded_bytes += size
        assert decoded_bytes <= MAX_DECODED and len(chunks) < 5000, "Decoded/chunk budget"
        chunk = {"tagHex": tag.hex(), "offset": start, "storedBytes": cursor.at - start,
                 "compressedBytes": compressed, "decodedBytes": size, "rawSHA256": sha(raw[start:cursor.at]),
                 "payloadSHA256": sha(payload), "decoded": False}
        chunks.append(chunk)
        item = Cursor(payload)
        if tag == b"INST":
            kind, class_name, object_format, count = item.u32(), item.string().decode("utf-8"), item.u8(), item.u32()
            assert kind not in classes and object_format in (0, 1) and 0 < count <= total, "Duplicate/invalid INST"
            referents = refs(item, count)
            assert all(ref >= 0 and ref not in nodes for ref in referents) and len(set(referents)) == count, "Duplicate/negative native identity"
            service_markers = item.take(count) if object_format == 1 else b""
            assert all(marker in (0, 1) for marker in service_markers), "Invalid service marker"
            item.done()
            classes[kind] = {"class": class_name, "referents": referents, "objectFormat": object_format,
                             "serviceMarkersHex": service_markers.hex()}
            for ref in referents: nodes[ref] = {"class": class_name, "typeID": kind}
            chunk["decoded"] = True
        elif tag == b"PROP":
            kind, name = item.u32(), item.string().decode("utf-8")
            assert kind in classes and name and (kind, name) not in properties, "Unknown/duplicate PROP owner or name"
            code = item.u8(); count = len(classes[kind]["referents"])
            column = {"class": classes[kind]["class"], "typeID": kind, "name": name, "typeCode": code,
                      "chunkIndex": len(chunks) - 1, "rawValueOffsetInPayload": item.at,
                      "rawValueBytes": len(payload) - item.at, "rawValueSHA256": sha(payload[item.at:]), "decoded": False}
            if code == 0x13:
                values = refs(item, count); item.done(); column["values"] = values; column["decoded"] = True
            elif name == "Name":
                assert code == 0x01, "Name must be an actual raw string column"
                values = [item.string().decode("utf-8") for _ in range(count)]; item.done()
                for ref, value in zip(classes[kind]["referents"], values): nodes[ref]["name"] = value
                column["values"] = values; column["decoded"] = True
            properties[kind, name] = column
            chunk["property"] = {k: v for k, v in column.items() if k != "values"}
            chunk["decoded"] = column["decoded"]
        elif tag == b"PRNT":
            assert not parents and item.u8() == 0, "Duplicate/unsupported PRNT"
            count = item.u32(); assert count == total, "Full PRNT coverage required"
            subjects, ancestors = refs(item, count), refs(item, count); item.done()
            assert len(set(subjects)) == count and set(subjects) == set(nodes), "PRNT identities differ"
            parents = dict(zip(subjects, ancestors)); chunk["decoded"] = True
        elif tag == b"END\0":
            assert payload == b"</roblox>" and cursor.at == len(raw), "Wrong/misplaced END or trailing file bytes"
            chunk["decoded"] = True; ended = True; break
        # META/SSTR/SIGN/future chunks are preserved by offset/hash in the raw input.
    assert ended and len(classes) == types and len(nodes) == total and len(parents) == total, "Incomplete binary forest"
    assert all("name" in node for node in nodes.values()), "Missing raw Name column"
    for ref, parent in parents.items():
        assert parent == -1 or parent in nodes, "Unresolved PRNT"
        seen, current = set(), ref
        while current != -1:
            assert current not in seen, "PRNT cycle"
            seen.add(current); current = parents[current]
    for column in properties.values():
        if column["typeCode"] == 0x13:
            assert all(value == -1 or value in nodes for value in column["values"]), "Unresolved raw Ref preserved as blocker, not null"
    return {"nodes": nodes, "parents": parents, "classes": classes, "properties": properties, "chunks": chunks,
            "rawSHA256": sha(raw), "rawBytes": len(raw), "decodedBytes": decoded_bytes}


def inspect(raw, expected_welds=109):
    dom = parse(raw); nodes, parents, properties = dom["nodes"], dom["parents"], dom["properties"]
    roots = [ref for ref in nodes if parents[ref] == -1]
    targets, by_name = set(), {}
    for ref in roots:
        row = nodes[ref]
        if row["name"] in NAMES:
            assert row["class"] == "Folder" and row["name"] not in by_name, "Duplicate/wrong old target root"
            by_name[row["name"]] = ref
    assert set(by_name) == set(NAMES), "All five target roots required"
    for name, count in zip(NAMES, COUNTS):
        root = by_name[name]; subset = set()
        for ref in nodes:
            current = ref
            while current != -1 and current != root: current = parents[current]
            if current == root: subset.add(ref)
        assert len(subset) == count, "Exact old subtree count differs"
        assert not targets.intersection(subset), "Old target trees overlap"
        targets.update(subset)
    assert len(targets) == 1617 and Counter(nodes[ref]["class"] for ref in targets) == Counter(CLASSES), "Exact target class closure differs"
    starters = [ref for ref in nodes if nodes[ref]["class"] == "StarterPlayer"]
    welds = [ref for ref in nodes if nodes[ref]["class"] == "WeldConstraint"]
    assert len(starters) == 1 and starters[0] in roots and nodes[starters[0]]["name"] == "StarterPlayer", "StarterPlayer root coverage differs"
    assert len(welds) == expected_welds, "Exact WeldConstraint coverage differs"
    assert all(ref in by_name.values() or ref == starters[0] or nodes[ref]["class"] == "WeldConstraint" for ref in roots), "Unexpected joint root"
    required, inbound = [], []
    for class_name, names in (("WeldConstraint", ("Part0Internal", "Part1Internal")), ("StarterPlayer", ("PlaceAvatarRules",))):
        kinds = [kind for kind, row in dom["classes"].items() if row["class"] == class_name]
        assert kinds, "Required raw class absent"
        for kind in kinds:
            for name in names:
                column = properties.get((kind, name))
                assert column is not None and column["typeCode"] == 0x13 and column["decoded"], "Required protected raw Ref column absent/wrong type: " + class_name + "." + name
                owners = dom["classes"][kind]["referents"]
                required.append({"class": class_name, "property": name, "rawTypeCode": 0x13, "owners": len(owners),
                                 "present": True, "rawValueSHA256": column["rawValueSHA256"], "values": column["values"]})
                for owner, value in zip(owners, column["values"]):
                    if value in targets: inbound.append({"ownerReferent": owner, "property": name, "targetReferent": value})
    assert not inbound, "Protected serialized inbound reference to retired forest: " + repr(inbound[:8])
    return {"schema": "retired-authoring-raw-protected-reference-fields-v1", "rawProtectedFieldsPassed": True,
            "referenceAbsenceCertified": False, "deletionApproved": False, "rawSHA256": dom["rawSHA256"], "rawBytes": dom["rawBytes"],
            "targetNodes": len(targets), "weldConstraints": len(welds), "requiredFields": required,
            "protectedSerializedInbound": inbound, "rawChunkInventory": dom["chunks"],
            "opaquePropertyColumns": [{k: v for k, v in row.items() if k != "values"} for row in properties.values() if not row["decoded"]],
            "limits": "Only the three required raw protected Ref fields against included five-forest referents. Opaque payloads remain in unchanged raw input. Nonserialized protected slots and fresh final removal CAS remain pending."}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--raw", type=Path, required=True)
    parser.add_argument("--receipt", type=Path, required=True)
    args = parser.parse_args(); assert not args.receipt.exists() and args.receipt.parent.is_dir()
    raw = args.raw.read_bytes()
    receipt = {"passed": False, "rawSHA256": sha(raw), "rawBytes": len(raw), "deletionApproved": False}
    try:
        receipt.update(inspect(raw)); receipt["passed"] = True
    except BaseException as error:
        receipt["error"] = str(error); raise
    finally:
        assert args.raw.read_bytes() == raw, "Raw input drift"
        with args.receipt.open("xb") as stream: stream.write((json.dumps(receipt, indent=2) + "\n").encode())


if __name__ == "__main__": main()
