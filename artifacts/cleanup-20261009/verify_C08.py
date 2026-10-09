"""Read-only verification of C08's exact comment deletion and compiled structure.

The only filesystem writes are compiler inputs inside an automatically cleaned
TemporaryDirectory. Production sources, manifest, native Studio, and checkpoints
are never changed. Supply --before when the local rollback checkpoint is absent.
"""
import argparse
import hashlib
import json
import os
from pathlib import Path
import shutil
import subprocess
import tempfile

SHA = lambda data: hashlib.sha256(data).hexdigest()

def varint(value):
    out = bytearray()
    while value >= 128:
        out.append((value & 127) | 128)
        value >>= 7
    out.append(value)
    return bytes(out)


def canonical(data):
    """Parse official version14 layout, zero only Proto.linedefined, resize Proto."""
    pos = 0

    def take(count):
        nonlocal pos
        assert pos + count <= len(data)
        result = data[pos:pos + count]
        pos += count
        return result

    def byte():
        return take(1)[0]

    def integer():
        result = shift = 0
        while True:
            value = byte()
            result |= (value & 127) << shift
            if value < 128:
                return result
            shift += 7
            assert shift <= 63

    version, types = byte(), byte()
    assert (version, types) == (14, 3), (version, types)
    strings = integer()
    for _ in range(strings):
        take(integer())
    while byte() != 0:
        integer()  # userdata name's string reference
    count = integer()
    out = bytearray(data[:pos])
    metadata = []
    for proto in range(count):
        size = integer()
        start = pos
        maxstack, params, upvalues, variadic, flags = (byte() for _ in range(5))
        take(integer())  # typeinfo payload
        instructions = integer()
        take(instructions * 4)  # all opcodes and AUX words are retained verbatim
        constants = integer()
        for _ in range(constants):
            tag = byte()
            if tag == 0:
                pass
            elif tag == 1:
                take(1)
            elif tag == 2:
                take(8)
            elif tag in (3, 6):
                integer()
            elif tag == 4:
                take(4)
            elif tag == 5:
                for _ in range(integer()):
                    integer()
            elif tag == 7:
                take(16)
            elif tag == 8:
                for _ in range(integer()):
                    integer()
                    take(4)
            elif tag == 9:
                take(1)
                integer()
            elif tag == 10:
                integer()
                properties, methods = integer(), integer()
                for _ in range(properties + methods):
                    integer()
            elif tag == 11:
                take(32)
            else:
                raise AssertionError((proto, tag))
        children = integer()
        for _ in range(children):
            integer()
        line_start = pos
        line = integer()
        line_end = pos
        debugname = integer()
        assert byte() == 0, "-g0 must omit lineinfo"
        assert byte() == 0, "-g0 must omit local/upvalue debug info"
        feedback = integer()
        for _ in range(feedback):
            assert byte() == 0
            integer()
        if flags & 8:
            integer()  # version12+ inlinable cost; preserve raw payload
        assert pos == start + size, (proto, pos, start, size)
        body = data[start:line_start] + b"\0" + data[line_end:pos]
        out.extend(varint(len(body)))
        out.extend(body)
        metadata.append({"proto": proto, "line": line, "lineOffset": line_start,
                         "lineBytes": line_end - line_start, "serializedBytes": size,
                         "maxstack": maxstack, "params": params, "upvalues": upvalues,
                         "variadic": variadic, "flags": flags, "instructions": instructions,
                         "constants": constants, "children": children, "debugname": debugname,
                         "feedback": feedback})
    main_start = pos
    integer()  # main proto ID
    assert pos == len(data)
    out.extend(data[main_start:pos])
    return bytes(out), metadata


def main():
    root = Path(__file__).resolve().parents[2]
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--before", type=Path, default=root / ".git/mongotv-cleanup-20261009/client-before/JumpscareUI.LocalScript.lua")
    parser.add_argument("--after", type=Path, default=root / "StarterPlayer/StarterPlayerScripts/JumpscareUI.LocalScript.lua")
    parser.add_argument("--compiler", default=os.environ.get("LUAU_COMPILE_BIN") or shutil.which("luau-compile"))
    parser.add_argument("--json", action="store_true", help="Print complete structured evidence to stdout.")
    args = parser.parse_args()
    if not args.compiler:
        parser.error("Set LUAU_COMPILE_BIN or pass --compiler pointing to Luau0.737 luau-compile.")
    before = args.before.read_bytes().replace(b"\r\n", b"\n")
    after = args.after.read_bytes().replace(b"\r\n", b"\n")
    assert SHA(before) == "07baa4a3ae035615dacb67da55ec197cfd4a09f6bf7071280f3685b653f97f88", "Original source integrity changed"
    assert SHA(after) == "7e5cedc84631a6af3f7edc126cb6775c9c498f42e851484c4980c3a3a6846a88", "C08 candidate integrity changed"
    start = before.index(b"--[[\nLEGACY IMAGE JUMPSCARE")
    end = before.index(b"]]\n", start) + 3
    block = before[start:end]
    assert block.count(b"\n") == 14
    assert block.count(b"--[[") == 1 and block.count(b"]]") == 1
    assert after == before[:start] + before[end:], "Difference beyond exact comment deletion"
    padded = before[:start] + b"\n" * 14 + before[end:]
    results = []
    with tempfile.TemporaryDirectory(prefix="c08-verify-") as folder:
        probe = Path(folder) / "JumpscareUI.lua"
        for optimization in (0, 1):
            outputs, dumps = {}, {}
            for label, body in (("before", before), ("after", after), ("linePreserved", padded)):
                probe.write_bytes(body)
                options = ["-g0", f"-O{optimization}", str(probe)]
                outputs[label] = subprocess.run([args.compiler, "--binary", *options], check=True, capture_output=True, timeout=30).stdout
                dumps[label] = subprocess.run([args.compiler, "--text", "--dump-constants", *options], check=True, capture_output=True, timeout=30).stdout
            assert dumps["before"] == dumps["after"] == dumps["linePreserved"], "Instruction/constant/upvalue dumps differ"
            assert outputs["before"] == outputs["linePreserved"], "Line-preserved raw bytecode differs"
            left, left_meta = canonical(outputs["before"])
            right, right_meta = canonical(outputs["after"])
            assert left == right, "Bytecode difference beyond linedefined/proto-size metadata"
            assert len(left_meta) == len(right_meta) == 14
            shifts = [{"proto": a["proto"], "beforeLine": a["line"], "afterLine": b["line"],
                       "beforeLineBytes": a["lineBytes"], "afterLineBytes": b["lineBytes"],
                       "beforeProtoBytes": a["serializedBytes"], "afterProtoBytes": b["serializedBytes"]}
                      for a, b in zip(left_meta, right_meta) if a["line"] != b["line"]]
            assert len(shifts) == 13 and all(item["beforeLine"] - item["afterLine"] == 14 for item in shifts)
            assert left_meta[-1]["line"] == right_meta[-1]["line"] == 1
            results.append({"optimization": optimization, "debug": 0, "functions": len(left_meta),
                            "beforeBinaryBytes": len(outputs["before"]), "afterBinaryBytes": len(outputs["after"]),
                            "beforeBinarySha256": SHA(outputs["before"]), "afterBinarySha256": SHA(outputs["after"]),
                            "canonicalBytecodeSha256": SHA(left), "canonicalBytecodeIdentical": True,
                            "textWithConstantsIdentical": True, "textBytes": len(dumps["before"]),
                            "textSha256": SHA(dumps["before"]), "linePreservedBinaryIdentical": True,
                            "lineDefinitionShifts": shifts, "beforeProtoMetadata": left_meta})
    if args.json:
        print(json.dumps({"finding": "C08", "exactCommentDeletion": True, "removedBytes": len(block),
                          "removedLines": 14, "beforeSha256Lf": SHA(before), "afterSha256Lf": SHA(after),
                          "canonicalization": "Replace only each Proto.linedefined varint with zero and recompute enclosing proto-size varint; retain all other bytes.",
                          "results": results}, indent=2))
    else:
        print("C08 PASS: exact461-byte/14-line comment deletion; O0/O1 all opcode/constant/upvalue/proto structures identical.")
        print("Only13 function definitions shift14 source lines; top-level line1 retained. No project/Studio mutation.")


if __name__ == "__main__":
    main()
