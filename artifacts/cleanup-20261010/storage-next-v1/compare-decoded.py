"""Compare two read-only Lune XML views without editing or normalizing data."""
from pathlib import Path
import collections
import hashlib
import json
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
PINNED = {
    "original": (24771888, "1ce8f12e91951dad4895132dd764f9cdd4e0e050116ffa6dfb72dfa4d58e9b9f"),
    "roundtrip": (24771890, "811d032cb0dcae98279b79b7cce33a579f55c8fa6670d85e5bfb2bdd4bf1d210"),
}

def sha(raw):
    return hashlib.sha256(raw).hexdigest()

def view(name):
    raw = (OUT / f"{name}.rbxmx").read_bytes()
    assert (len(raw), sha(raw)) == PINNED[name], "Frozen offline XML changed"
    document = ET.fromstring(raw)
    rows, referents = {}, {}

    def visit(item, parents):
        props = item.find("Properties")
        assert props is not None
        name_prop = next(p for p in props if p.attrib["name"] == "Name")
        node_name = name_prop.text or ""
        siblings = [s for s in item if s.tag == "Item"]
        path = parents + [(item.attrib["class"], node_name)]
        key = json.dumps(path, separators=(",", ":"), ensure_ascii=False)
        # These archives contain identically named siblings. Record deterministic
        # child ordinal only for duplicate class/name slots in the same parent.
        assert key not in rows, "Ambiguous diagnostic identity"
        rows[key] = {"path": path, "class": item.attrib["class"], "properties": {p.attrib["name"]: p for p in props}}
        referents[item.attrib["referent"]] = key
        counts = collections.Counter((s.attrib["class"], s.find("Properties/string[@name='Name']").text or "") for s in siblings)
        ordinals = collections.Counter()
        for s in siblings:
            pair = (s.attrib["class"], s.find("Properties/string[@name='Name']").text or "")
            ordinals[pair] += 1
            suffix = [("__diagnostic_duplicate_ordinal__", str(ordinals[pair]))] if counts[pair] > 1 else []
            visit(s, path + suffix)

    for item in document:
        if item.tag == "Item":
            visit(item, [])
    return rows, referents

before, before_refs = view("original")
after, after_refs = view("roundtrip")
assert before.keys() == after.keys(), "Lune hierarchy differs"
differences = []
for key in sorted(before):
    row_a, row_b = before[key], after[key]
    assert row_a["class"] == row_b["class"]
    props_a, props_b = row_a["properties"], row_b["properties"]
    assert props_a.keys() == props_b.keys(), "Decoded property inventory differs"
    for prop in sorted(props_a):
        a, b = props_a[prop], props_b[prop]
        assert a.tag == b.tag
        if a.tag == "Ref":
            assert before_refs.get(a.text, a.text) == after_refs.get(b.text, b.text), "Offline referent differs"
            continue
        raw_a, raw_b = ET.tostring(a), ET.tostring(b)
        if raw_a == raw_b:
            continue
        # Only numeric CFrame components are emitted, never Source/string bodies.
        scalar_changes = []
        for aa, bb in zip(a.iter(), b.iter(), strict=True):
            assert aa.tag == bb.tag and aa.attrib == bb.attrib
            if aa.text != bb.text:
                av, bv = (aa.text or "").strip(), (bb.text or "").strip()
                if aa.tag in {"X", "Y", "Z", "R00", "R01", "R02", "R10", "R11", "R12", "R20", "R21", "R22"}:
                    scalar_changes.append({"component": aa.tag, "before": av, "after": bv,
                        "delta": float(bv) - float(av)})
                else:
                    scalar_changes.append({"component": aa.tag, "bodyOmitted": True,
                        "beforeTextSHA256": sha(av.encode()), "afterTextSHA256": sha(bv.encode())})
        differences.append({"path": row_a["path"], "class": row_a["class"], "property": prop,
            "xmlType": a.tag, "beforePropertySHA256": sha(raw_a), "afterPropertySHA256": sha(raw_b),
            "scalarChanges": scalar_changes})

report = {"schema": "s06-offline-lune-property-diff-v1", "nativeCalls": 0, "nativeWrites": 0,
    "restorationCertified": False, "normalizationApplied": False, "decodedInstances": len(before),
    "decodedPropertiesCompared": sum(len(row["properties"]) for row in before.values()),
    "propertyDifferenceCount": len(differences), "differences": differences,
    "inputs": {name: {"path": f"{name}.rbxmx", "bytes": count, "sha256": digest} for name, (count, digest) in PINNED.items()},
    "limits": "Historical binary Lune decode diagnostic; it cannot certify native ReflectionService-readable data, opaque engine fields, live originals, runtime serialization-only fields, or actual restoration."}
output = OUT / "offline-differences.json"
assert not output.exists(), "Refusing existing diagnostic receipt"
with output.open("xb") as stream:
    stream.write((json.dumps(report, indent=2, ensure_ascii=False) + "\n").encode())
print(json.dumps({"decodedInstances": len(before), "propertyDifferences": len(differences), "output": str(output)}, ensure_ascii=False))
