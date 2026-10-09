"""Offline serialized reference closure for 12 diagnostic Folders + StarterPlayer.

Run from any cwd with --lune PATH --archive DIRECTORY --receipt NEW.json.
Uses only local Lune serialization and stdlib XML parsing; never connects to Studio.
"""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import tempfile
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[2]
HELPER = ROOT / "tools/cleanup_20261009/dump_diagnostic_reference_forest.luau"
NAMES = {
    "TEMP_PipeEntityLobbyRigResult_0748Z",
    *(f"TEMP_PipeEntityMPResult_{suffix}" for suffix in (
        "0457Z", "0503Z", "0508Z", "0638Z", "0706Z", "1609Z", "1624Z",
        "1633Z", "1640Z", "1648Z")),
    "TEMP_PipeEntityMultiplayerLaunch",
}


def sha(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def inspect_xml(data: bytes) -> dict:
    assert b"<!DOCTYPE" not in data.upper() and b"<!ENTITY" not in data.upper(), "DTD/entities refused"
    document = ET.fromstring(data)
    assert document.tag == "roblox", "Wrong XML root"
    roots = document.findall("Item")
    assert len(roots) == 13, "Reference forest must have 13 direct roots"
    referents: dict[str, ET.Element] = {}
    owners: dict[ET.Element, tuple[str, str, str]] = {}
    target_refs: set[str] = set()
    target_names: set[str] = set()
    starter: ET.Element | None = None

    def visit(item: ET.Element, parent_path: str = "") -> None:
        assert item.get("class"), "Missing Item class"
        ref = item.get("referent")
        assert ref and ref != "null" and ref not in referents, "Missing/duplicate Item referent"
        referents[ref] = item
        props = item.findall("Properties")
        assert len(props) == 1, "Item must have exactly one Properties block"
        names = [p for p in props[0] if p.get("name") == "Name"]
        assert len(names) == 1 and names[0].tag == "string" and not list(names[0]), "Invalid/duplicate Name property"
        name = names[0].text or ""
        path = f"{parent_path}.{name}" if parent_path else name
        property_names: set[str] = set()
        for prop in props[0]:
            property_name = prop.get("name")
            assert property_name and property_name not in property_names, "Missing/duplicate native property"
            property_names.add(property_name)
            if prop.tag == "Ref":
                assert not list(prop), "Nested Ref value refused"
                owners[prop] = (path, item.get("class") or "", property_name)
        for child in item.findall("Item"):
            visit(child, path)

    for item in roots:
        visit(item)
        props = item.find("Properties")
        assert props is not None
        name = next(p.text or "" for p in props if p.get("name") == "Name")
        if item.get("class") == "StarterPlayer":
            assert starter is None and name == "StarterPlayer", "Unexpected StarterPlayer identity"
            starter = item
        else:
            assert item.get("class") == "Folder" and name in NAMES, "Unexpected target identity"
            assert name not in target_names and not item.findall("Item"), "Duplicate/nonempty target Folder"
            target_names.add(name)
            target_refs.add(item.get("referent") or "")
    assert target_names == NAMES and starter is not None, "Target set/StarterPlayer missing"
    assert len(list(document.iter("Item"))) == len(referents), "Item outside native root/child hierarchy"
    refs = list(document.iter("Ref"))
    assert len(refs) == len(owners), "Ref outside native Item Properties"
    inbound = []
    for ref in refs:
        value = (ref.text or "").strip()
        assert value == "null" or value in referents, "Unresolved/empty serialized Ref"
        if value in target_refs:
            path, cls, prop = owners[ref]
            inbound.append({"owner": path, "class": cls, "property": prop})
    assert not inbound, f"Serialized inbound references to diagnostic targets: {inbound}"
    avatar = [p for p in starter.find("Properties") if p.get("name") == "PlaceAvatarRules"]
    assert len(avatar) <= 1 and (not avatar or avatar[0].tag == "Ref"), "Wrong PlaceAvatarRules property type"
    return {
        "rootCount": 13, "targetCount": 12, "itemCount": len(referents),
        "serializedRefCount": len(refs), "serializedInboundReferences": [],
        "placeAvatarRules": "serialized null" if avatar else "absent canonical property (default null)",
    }


def verify_archive(lune: Path, archive: Path) -> dict:
    facts_path = archive / "facts.json"
    refs_path = archive / "references.rbxm"
    facts_raw, refs_raw = facts_path.read_bytes(), refs_path.read_bytes()
    facts = json.loads(facts_raw)
    assert facts["schema"] == "folder-diagnostic-archive-v1", "Wrong archive schema"
    assert (facts["placeId"], facts["universeId"]) == (131311258779917, 10559217407), "Wrong archive place"
    assert len(refs_raw) == facts["referencesBytes"] and sha(refs_raw) == facts["referencesSHA256"], "Reference hash/length differs"
    with tempfile.TemporaryDirectory(prefix="mongotv-reference-closure-") as owned:
        xml_path = Path(owned) / "joint-forest.rbxmx"
        result = subprocess.run([str(lune), "run", str(HELPER), str(facts_path),
                                 str(refs_path), str(xml_path)], cwd=ROOT,
                                text=True, encoding="utf-8", capture_output=True, timeout=90)
        assert result.returncode == 0 and xml_path.is_file(), "Lune reference export failed: " + result.stderr[:2000]
        helper_receipt = json.loads(result.stdout.strip())
        xml = xml_path.read_bytes()
        assert helper_receipt["verified"] and sha(xml) == helper_receipt["xmlSHA256"], "XML transfer receipt differs"
        report = inspect_xml(xml)
    assert facts_path.read_bytes() == facts_raw and refs_path.read_bytes() == refs_raw, "Reference input changed"
    report.update({
        "schema": "diagnostic-folder-serialized-reference-closure-v1", "verified": True,
        "factsSHA256": sha(facts_raw), "referencesSHA256": sha(refs_raw),
        "referencesBytes": len(refs_raw), "xmlSHA256": sha(xml),
        "canonicalSHA256": helper_receipt["canonicalSHA256"],
        "verifierSHA256": sha(Path(__file__).read_bytes()), "helperSHA256": sha(HELPER.read_bytes()),
        "limits": "Only references serialized in the joint forest of these 12 Folders and StarterPlayer. Live global readable-property/ObjectValue scan, protected nonserialized exceptions, current selection and CAS are separate native gates. No gameplay or performance claim.",
    })
    return report


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lune", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args()
    assert not args.receipt.exists(), "Refusing existing receipt path"
    report = verify_archive(args.lune.resolve(), args.archive.resolve())
    with args.receipt.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({key: report[key] for key in ("verified", "targetCount", "serializedRefCount", "placeAvatarRules", "referencesSHA256")}))


if __name__ == "__main__":
    main()
