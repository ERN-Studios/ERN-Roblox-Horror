"""Offline actual-archive and independent XML reference-corruption fixtures."""
from __future__ import annotations

import argparse
import copy
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import xml.etree.ElementTree as ET

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("reference_verifier", HERE / "verify_diagnostic_folder_references.py")
verifier = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(verifier)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--lune", required=True, type=Path)
    parser.add_argument("--archive", required=True, type=Path)
    parser.add_argument("--receipt", required=True, type=Path)
    args = parser.parse_args()
    assert not args.receipt.exists(), "Refusing existing test receipt"
    lune, archive = args.lune.resolve(), args.archive.resolve()
    original_facts = (archive / "facts.json").read_bytes()
    original_native = (archive / "native.rbxm").read_bytes()
    original_refs = (archive / "references.rbxm").read_bytes()
    facts = json.loads(original_facts)
    checks, positive, negative, cases = 0, 0, 0, []

    def check(value: bool, label: str) -> None:
        nonlocal checks
        checks += 1
        assert value, label

    def accept(label: str, document: bytes) -> None:
        nonlocal positive
        report = verifier.inspect_xml(document)
        check(report["targetCount"] == 12 and not report["serializedInboundReferences"], label)
        positive += 1
        cases.append({"name": label, "expected": "accept", "passed": True})

    def reject(label: str, callback, expected: str) -> None:
        nonlocal negative
        try:
            callback()
        except (AssertionError, ET.ParseError) as exc:
            check(expected in str(exc), "Wrong failure reason: " + label)
        else:
            raise AssertionError("Accepted invalid case: " + label)
        negative += 1
        cases.append({"name": label, "expected": "reject", "passed": True})

    actual = verifier.verify_archive(lune, archive)
    check(actual["verified"] and actual["placeAvatarRules"] == "serialized null", "Actual native forest failed")
    positive += 1
    cases.append({"name": "actual native joint forest", "expected": "accept", "passed": True})

    # Separate hand-authored fixtures use captured names, never verifier-generated XML.
    document = ET.Element("roblox", version="4")
    for index, row in enumerate(facts["roots"]):
        item = ET.SubElement(document, "Item", {"class": "Folder", "referent": f"TARGET{index}"})
        props = ET.SubElement(item, "Properties")
        ET.SubElement(props, "string", name="Name").text = row["name"]
    starter = ET.SubElement(document, "Item", {"class": "StarterPlayer", "referent": "STARTER"})
    props = ET.SubElement(starter, "Properties")
    ET.SubElement(props, "string", name="Name").text = "StarterPlayer"
    ET.SubElement(props, "Ref", name="PlaceAvatarRules").text = "null"

    def xml(value: ET.Element) -> bytes:
        return ET.tostring(value, encoding="utf-8")

    def mutated(label: str, mutate, expected: str) -> None:
        value = copy.deepcopy(document)
        mutate(value)
        reject(label, lambda: verifier.inspect_xml(xml(value)), expected)

    accept("independent null-reference forest", xml(document))
    reordered = copy.deepcopy(document)
    reordered[:] = list(reversed(list(reordered)))
    accept("root-order independence", xml(reordered))
    nested = copy.deepcopy(document)
    item = ET.SubElement(nested[-1], "Item", {"class": "ObjectValue", "referent": "NESTED"})
    props = ET.SubElement(item, "Properties")
    ET.SubElement(props, "string", name="Name").text = "Pointer"
    ET.SubElement(props, "Ref", name="Value").text = "STARTER"
    accept("genuine non-target ObjectValue reference", xml(nested))
    protected = xml(document).replace(b'</Properties></Item></roblox>',
        b'<ProtectedString name="Source"><![CDATA[<Item class="Folder" referent="FAKE"><Ref name="Value">TARGET0</Ref></Item>]]></ProtectedString>'
        b'</Properties><!-- <Ref name="Value">TARGET0</Ref> --></Item></roblox>')
    check(b"<![CDATA[" in protected and b"<!--" in protected, "Pseudo-tag fixture not constructed")
    accept("CDATA/source and comment pseudo-tags ignored", protected)

    mutated("protected PlaceAvatarRules points at target", lambda v: setattr(v[-1].find("Properties/Ref"), "text", "TARGET0"), "Serialized inbound references")
    inbound_nested = copy.deepcopy(nested)
    inbound_nested[-1].find("Item/Properties/Ref").text = "TARGET0"
    reject("nested ObjectValue.Value points at target", lambda: verifier.inspect_xml(xml(inbound_nested)), "Serialized inbound references")
    mutated("unknown serialized property points at target", lambda v: setattr(ET.SubElement(v[0].find("Properties"), "Ref", name="FutureProperty"), "text", "TARGET1"), "Serialized inbound references")
    mutated("duplicate root referent", lambda v: v[1].set("referent", "TARGET0"), "Missing/duplicate Item referent")
    nested_collision = copy.deepcopy(nested)
    nested_collision[-1].find("Item").set("referent", "TARGET0")
    reject("nested referent collision", lambda: verifier.inspect_xml(xml(nested_collision)), "Missing/duplicate Item referent")
    mutated("missing referent", lambda v: v[0].attrib.pop("referent"), "Missing/duplicate Item referent")
    mutated("wrong target class", lambda v: v[0].set("class", "Model"), "Unexpected target identity")
    mutated("wrong StarterPlayer identity", lambda v: v[-1].find("Properties/string").__setattr__("text", "Other"), "Unexpected StarterPlayer identity")
    mutated("missing direct root", lambda v: v.remove(v[0]), "13 direct roots")
    mutated("extra direct root", lambda v: v.append(copy.deepcopy(v[0])), "13 direct roots")
    mutated("duplicate target name", lambda v: v[1].find("Properties/string").__setattr__("text", v[0].find("Properties/string").text), "Duplicate/nonempty target Folder")
    mutated("unknown target name", lambda v: v[0].find("Properties/string").__setattr__("text", "Other"), "Unexpected target identity")
    mutated("duplicate Name property", lambda v: v[0].find("Properties").append(copy.deepcopy(v[0].find("Properties/string"))), "Invalid/duplicate Name property")
    mutated("missing Properties", lambda v: v[0].remove(v[0].find("Properties")), "exactly one Properties")
    mutated("duplicate Properties", lambda v: v[0].append(copy.deepcopy(v[0].find("Properties"))), "exactly one Properties")
    nonempty = copy.deepcopy(document)
    item = ET.SubElement(nonempty[0], "Item", {"class": "Folder", "referent": "CHILD"})
    ET.SubElement(ET.SubElement(item, "Properties"), "string", name="Name").text = "Child"
    reject("target Folder gains child", lambda: verifier.inspect_xml(xml(nonempty)), "Duplicate/nonempty target Folder")
    mutated("Ref outside Properties", lambda v: setattr(ET.SubElement(v, "Ref", name="Value"), "text", "TARGET0"), "Ref outside native Item")
    misplaced = copy.deepcopy(document)
    wrapper = ET.SubElement(misplaced, "UnexpectedWrapper")
    item = ET.SubElement(wrapper, "Item", {"class": "Folder", "referent": "MISPLACED"})
    ET.SubElement(ET.SubElement(item, "Properties"), "string", name="Name").text = "Hidden"
    reject("Item outside native hierarchy", lambda: verifier.inspect_xml(xml(misplaced)), "Item outside native root/child hierarchy")
    mutated("Ref contains child markup", lambda v: ET.SubElement(v[-1].find("Properties/Ref"), "string"), "Nested Ref value refused")
    mutated("unresolved Ref", lambda v: setattr(v[-1].find("Properties/Ref"), "text", "MISSING"), "Unresolved/empty serialized Ref")
    mutated("wrong PlaceAvatarRules type", lambda v: setattr(v[-1].find("Properties/Ref"), "tag", "string"), "Wrong PlaceAvatarRules property type")
    reject("DOCTYPE/entity expansion refused", lambda: verifier.inspect_xml(b'<!DOCTYPE roblox [<!ENTITY leak "x">]>' + xml(document)), "DTD/entities refused")
    reject("malformed XML refused", lambda: verifier.inspect_xml(b"<roblox><Item></roblox>"), "mismatched tag")

    with tempfile.TemporaryDirectory(prefix="mongotv-reference-negative-") as owned:
        clone = Path(owned)
        (clone / "facts.json").write_bytes(original_facts)
        (clone / "references.rbxm").write_bytes(b"X" + original_refs[1:])
        reject("actual binary digest corruption", lambda: verifier.verify_archive(lune, clone), "Reference hash/length differs")
        (clone / "references.rbxm").write_bytes(original_refs)
        bad_facts = copy.deepcopy(facts)
        bad_facts["referencesBytes"] += 1
        (clone / "facts.json").write_text(json.dumps(bad_facts), encoding="utf-8")
        reject("actual reference length metadata corruption", lambda: verifier.verify_archive(lune, clone), "Reference hash/length differs")
        sentinel = clone / "sentinel.json"
        sentinel.write_bytes(b"existing receipt must remain unchanged\n")
        old = sentinel.read_bytes()
        result = subprocess.run([sys.executable, "-B", str(HERE / "verify_diagnostic_folder_references.py"),
                                 "--lune", str(lune), "--archive", str(archive), "--receipt", str(sentinel)],
                                capture_output=True, timeout=10)
        check(result.returncode != 0 and sentinel.read_bytes() == old, "Existing receipt overwritten")
        negative += 1
        cases.append({"name": "existing CLI receipt preserved", "expected": "reject", "passed": True})
        # Also exercise the public Folder-archive CLI, rather than only its module.
        archive_receipt = clone / "folder-cli.json"
        archive_runner = HERE / "verify_diagnostic_folder_archive.luau"
        cli_args = [str(lune), "run", str(archive_runner), str(archive / "facts.json"),
                    str(archive / "native.rbxm"), str(archive_receipt)]
        result = subprocess.run(cli_args, cwd=verifier.ROOT, capture_output=True, timeout=30)
        check(result.returncode == 0 and archive_receipt.is_file(), "Folder CLI did not produce receipt")
        check(json.loads(archive_receipt.read_text())["verified"], "Folder CLI receipt failed")
        positive += 1
        cases.append({"name": "actual Folder public CLI", "expected": "accept", "passed": True})
        before = archive_receipt.read_bytes()
        result = subprocess.run(cli_args, cwd=verifier.ROOT, capture_output=True, timeout=30)
        check(result.returncode != 0 and archive_receipt.read_bytes() == before, "Folder CLI overwrote existing receipt")
        negative += 1
        cases.append({"name": "Folder CLI existing receipt preserved", "expected": "reject", "passed": True})
        bad_folder_facts = copy.deepcopy(facts)
        bad_folder_facts["roots"][0]["attributes"]["Complete"]["type"] = "string"
        bad_facts_path = clone / "bad-folder-facts.json"
        bad_facts_path.write_text(json.dumps(bad_folder_facts), encoding="utf-8")
        refused_output = clone / "refused-folder-receipt.json"
        result = subprocess.run([str(lune), "run", str(archive_runner), str(bad_facts_path),
                                 str(archive / "native.rbxm"), str(refused_output)],
                                cwd=verifier.ROOT, capture_output=True, timeout=30)
        check(result.returncode != 0 and not refused_output.exists(), "Folder CLI wrote receipt for invalid facts")
        negative += 1
        cases.append({"name": "Folder CLI invalid facts produce no receipt", "expected": "reject", "passed": True})

    check((archive / "facts.json").read_bytes() == original_facts, "Immutable facts changed")
    check((archive / "native.rbxm").read_bytes() == original_native, "Immutable native changed")
    check((archive / "references.rbxm").read_bytes() == original_refs, "Immutable references changed")
    report = {"schema": "diagnostic-reference-offline-tests-v1", "passed": True,
              "checks": checks, "positiveCases": positive, "negativeCases": negative, "cases": cases,
              "actualSerializedRefCount": actual["serializedRefCount"],
              "factsSHA256": verifier.sha(original_facts), "referencesSHA256": verifier.sha(original_refs),
              "verifierSHA256": verifier.sha((HERE / "verify_diagnostic_folder_references.py").read_bytes()),
              "helperSHA256": verifier.sha(verifier.HELPER.read_bytes()), "testSHA256": verifier.sha(Path(__file__).read_bytes()),
              "limits": "Local XML/native fixtures only; no Studio or deletion/CAS operation."}
    with args.receipt.open("x", encoding="utf-8", newline="\n") as stream:
        json.dump(report, stream, indent=2)
        stream.write("\n")
    print(json.dumps({k: report[k] for k in ("passed", "checks", "positiveCases", "negativeCases", "actualSerializedRefCount")}))


if __name__ == "__main__":
    main()
