#!/usr/bin/env python3
"""Read-only verification of the 2026-10-01 shop icon replacement.

Usage:
  python3 verify_shop_icon_scope.py --after-config CONFIG.luau \
    --after-display DISPLAY.luau --published-mapping icon-map.json \
    --after-catalog studio-catalog-after.json --report scope-verification.json

Mapping may be {"EntityDetector": 123, ...}, {"icons": {key: id, ...}},
or a list/"rows"/"records"/"icons" list of {"key": key, "imageAssetId": id}.
Only the 14 utility keys are read; donation and portrait records are ignored.
The optional evaluated catalog comparison uses the fresh Studio export's
"catalogs" object, excluding capture metadata. It strips ONLY the 14 allowed
utility IconId fields before comparing all remaining evaluated catalog data.
Full Source comparison separately proves all functions and unrelated content
are byte-identical. This script never connects to or modifies Studio.
"""

from __future__ import annotations

import argparse
import copy
import hashlib
import json
from pathlib import Path
import re
import sys
from typing import Any


TASK = Path(__file__).resolve().parent
AUDIT = TASK / "audit"
UTILITY = (
    "EntityDetector", "Supporter", "AdvancedEquipment", "CosmeticEquipment",
    "ExpeditionPack", "Tokens4", "Tokens20", "EmergencyReentry",
    "TokenEarner2x", "TokenEarner3x", "TokenEarner5x",
    "TokenEarnerUp2to3", "TokenEarnerUp3to5", "TokenEarnerUp2to5",
)
WALL = UTILITY[:8]
PASS_KEYS = UTILITY[:4]
PRODUCT_KEYS = UTILITY[4:8]
EXPECTED_PLACE = 131311258779917
EXPECTED_UNIVERSE = 10559217407


class VerificationError(ValueError):
    pass


def require(condition: bool, message: str) -> None:
    if not condition:
        raise VerificationError(message)


def sha256(value: str) -> str:
    return hashlib.sha256(value.encode("utf-8")).hexdigest()


def read_source(path: Path) -> str:
    # Decode bytes directly to preserve CRLF and all surrounding Source bytes.
    return path.read_bytes().decode("utf-8")


def long_bracket_end(source: str, start: int) -> int | None:
    match = re.match(r"\[(=*)\[", source[start:])
    if not match:
        return None
    closing = "]" + match.group(1) + "]"
    stop = source.find(closing, start + match.end())
    require(stop >= 0, "Unterminated Luau long string or comment")
    return stop + len(closing)


def mask_noncode(source: str) -> str:
    """Mask strings and comments while preserving indices and newlines."""
    result = list(source)
    index = 0
    while index < len(source):
        end = None
        if source.startswith("--", index):
            end = long_bracket_end(source, index + 2)
            if end is None:
                newline = source.find("\n", index + 2)
                end = len(source) if newline < 0 else newline
        elif source[index] in "\"'`":
            quote = source[index]
            cursor = index + 1
            while cursor < len(source):
                if source[cursor] == "\\":
                    cursor += 2
                elif source[cursor] == quote:
                    end = cursor + 1
                    break
                else:
                    cursor += 1
            require(end is not None, "Unterminated Luau quoted string")
        elif source[index] == "[":
            end = long_bracket_end(source, index)
        if end is None:
            index += 1
            continue
        for cursor in range(index, end):
            if result[cursor] not in "\r\n":
                result[cursor] = " "
        index = end
    return "".join(result)


def unique_table(masked: str, key: str, start: int = 0,
                 end: int | None = None) -> tuple[int, int]:
    matches = list(re.finditer(r"\b" + re.escape(key) + r"\s*=\s*\{",
                              masked[start:end]))
    require(len(matches) == 1, f"Expected exactly one {key} table; found {len(matches)}")
    opening = start + matches[0].end() - 1
    depth = 0
    for cursor in range(opening, len(masked) if end is None else end):
        if masked[cursor] == "{":
            depth += 1
        elif masked[cursor] == "}":
            depth -= 1
            if depth == 0:
                return opening + 1, cursor
    raise VerificationError(f"Unbalanced {key} table")


def config_slots(source: str) -> dict[str, tuple[int, int, int]]:
    masked = mask_noncode(source)
    slots = {}
    for key in UTILITY:
        start, end = unique_table(masked, key)
        found = list(re.finditer(r"\bIconId\s*=\s*([0-9]+)\b", masked[start:end]))
        require(len(found) == 1, f"Expected one numeric {key}.IconId; found {len(found)}")
        match = found[0]
        slots[key] = (start + match.start(1), start + match.end(1), int(match.group(1)))
    return slots


def wall_slots(source: str) -> dict[str, tuple[int, int, int]]:
    masked = mask_noncode(source)
    start, end = unique_table(masked, "SHOP_TEXTURES")
    start, end = unique_table(masked, "Box", start, end)
    slots = {}
    for key in WALL:
        # Match the key in code, then read only its actual quoted URL value.
        found = list(re.finditer(r"\b" + re.escape(key) + r"\s*=", masked[start:end]))
        require(len(found) == 1, f"Expected one SHOP_TEXTURES.Box.{key}; found {len(found)}")
        value_start = start + found[0].end()
        value_match = re.match(r'\s*(["\'])rbxassetid://([0-9]+)\1', source[value_start:])
        require(value_match is not None, f"Expected quoted asset URL for SHOP_TEXTURES.Box.{key}")
        slots[key] = (value_start + value_match.start(2),
                      value_start + value_match.end(2), int(value_match.group(2)))
    return slots


def normalized(source: str, slots: dict[str, tuple[int, int, int]]) -> str:
    for key, (start, end, _) in sorted(slots.items(), key=lambda item: item[1][0], reverse=True):
        source = source[:start] + "<ALLOWED_ICON_ID:" + key + ">" + source[end:]
    return source


def mapping_ids(data: Any) -> dict[str, int]:
    if isinstance(data, dict) and "icons" in data:
        data = data["icons"]
    elif isinstance(data, dict) and "records" in data:
        data = data["records"]
    elif isinstance(data, dict) and "rows" in data:
        data = data["rows"]
    if isinstance(data, list):
        pairs = []
        for record in data:
            require(isinstance(record, dict), "Mapping row must be an object")
            key = record.get("key", record.get("Key"))
            if key in UTILITY:
                pairs.append((key, record))
        require(len(pairs) == len({key for key, _ in pairs}), "Duplicate utility key in mapping")
        data = dict(pairs)
    require(isinstance(data, dict), "Expected icon mapping object or records")
    result = {}
    for key in UTILITY:
        require(key in data, f"Published mapping missing {key}")
        value = data[key]
        if isinstance(value, dict):
            fields = ("imageAssetId", "ImageAssetId", "imageId", "ImageId", "assetId", "IconId")
            candidates = [value[name] for name in fields if name in value]
            require(bool(candidates), f"Published mapping has no raw image ID for {key}")
            value = candidates[0]
            require(all(str(other) == str(value) for other in candidates),
                    f"Conflicting raw image IDs for {key}")
        if isinstance(value, str) and value.startswith("rbxassetid://"):
            value = value[len("rbxassetid://"):]
        require(not isinstance(value, bool) and str(value).isdigit(), f"Invalid image ID for {key}")
        result[key] = int(value)
        require(result[key] > 0, f"Nonpositive image ID for {key}")
    return result


def verify_sources(before_config: str, after_config: str, before_display: str,
                   after_display: str, icon_ids: dict[str, int]) -> dict[str, Any]:
    records = []
    for label, before, after, extractor, count in (
        ("ReplicatedStorage.ZyntraConfig", before_config, after_config, config_slots, 14),
        ("ServerScriptService.LobbyShopDisplay", before_display, after_display, wall_slots, 8),
    ):
        before_slots, after_slots = extractor(before), extractor(after)
        require(len(before_slots) == count and len(after_slots) == count,
                f"Wrong allowed slot count for {label}")
        require(normalized(before, before_slots) == normalized(after, after_slots),
                f"{label}: Source changed outside the {count} allowed image ID literals")
        changed = []
        for key, (_, _, actual_id) in after_slots.items():
            require(actual_id == icon_ids[key], f"{label}.{key}: expected {icon_ids[key]}, got {actual_id}")
            old_id = before_slots[key][2]
            require(actual_id != old_id, f"{label}.{key}: old icon was not replaced")
            changed.append({"key": key, "before": old_id, "after": actual_id})
        records.append({"path": label, "before_sha256": sha256(before), "after_sha256": sha256(after),
                        "allowed_slot_count": count, "changed_slot_count": len(changed),
                        "remaining_source_byte_identical": True, "changes": changed})
    return {"passed": True, "source_scope": records,
            "price_product_pass_ids_grants_functions_and_surrounding_source_unchanged": True}


def catalog_namespace(key: str) -> str:
    return "Passes" if key in PASS_KEYS else "Products" if key in PRODUCT_KEYS else "TokenEarner"


def catalog_data(value: dict[str, Any]) -> dict[str, Any]:
    require(isinstance(value, dict) and isinstance(value.get("catalogs"), dict),
            "Evaluated Studio catalog JSON must contain a catalogs object")
    for name, expected in (("placeId", EXPECTED_PLACE), ("universeId", EXPECTED_UNIVERSE)):
        if name in value:
            require(value[name] == expected, f"Unexpected evaluated catalog {name}: {value[name]}")
    return value["catalogs"]


def compare_catalogs(before: dict[str, Any], after: dict[str, Any],
                     icon_ids: dict[str, int]) -> dict[str, Any]:
    original, revised = copy.deepcopy(catalog_data(before)), copy.deepcopy(catalog_data(after))
    for key in UTILITY:
        namespace = catalog_namespace(key)
        require(key in original.get(namespace, {}) and key in revised.get(namespace, {}),
                f"Evaluated catalog missing {namespace}.{key}")
        require("IconId" in original[namespace][key], f"Before catalog missing {key}.IconId")
        require(revised[namespace][key].get("IconId") == icon_ids[key],
                f"Evaluated after catalog has wrong {key}.IconId")
        del original[namespace][key]["IconId"]
        del revised[namespace][key]["IconId"]
    require(original == revised, "Evaluated catalog changed beyond the 14 utility IconIds")
    return {"performed": True, "passed": True, "stripped_utility_icon_fields": 14,
            "all_other_catalog_data_equal": True,
            "preserved_catalog_sha256": sha256(json.dumps(original, sort_keys=True, ensure_ascii=False))}


def replace_slots(source: str, extractor, icon_ids: dict[str, int]) -> str:
    for key, (start, end, _) in sorted(extractor(source).items(), key=lambda item: item[1][0], reverse=True):
        source = source[:start] + str(icon_ids[key]) + source[end:]
    return source


def self_test(before_config: str, before_display: str, before_catalog: dict[str, Any]) -> dict[str, Any]:
    # Negative controls exercise accidental price/grant/ID/function/other-art writes.
    icon_ids = {key: 800000000000000 + index for index, key in enumerate(UTILITY, 1)}
    config = replace_slots(before_config, config_slots, icon_ids)
    display = replace_slots(before_display, wall_slots, icon_ids)
    after_catalog = copy.deepcopy(before_catalog)
    for key in UTILITY:
        after_catalog["catalogs"][catalog_namespace(key)][key]["IconId"] = icon_ids[key]
    verify_sources(before_config, config, before_display, display, icon_ids)
    compare_catalogs(before_catalog, after_catalog, icon_ids)
    controls = {
        "price_change": config.replace("Price=149", "Price=150", 1),
        "grant_change": config.replace("TokenGrant = 10", "TokenGrant = 11", 1),
        "product_id_change": config.replace("Id = 3707755089", "Id = 3707755090", 1),
        "function_change": config.replace("return owns.TokenEarner2x and 2 or 1", "return owns.TokenEarner2x and 3 or 1", 1),
        "unrelated_item_icon_change": config.replace("IconId = 73457681182843", "IconId = 73457681182844", 1),
        "surrounding_comment_change": config + "\n-- unrelated write\n",
        "wrong_utility_image_id": config.replace(str(icon_ids["Supporter"]), str(icon_ids["Supporter"] + 100), 1),
    }
    rejected = []
    for name, mutation in controls.items():
        require(mutation != config, f"Self-test fixture did not create {name}")
        try:
            verify_sources(before_config, mutation, before_display, display, icon_ids)
        except VerificationError:
            rejected.append(name)
        else:
            raise VerificationError(f"Self-test accepted prohibited {name}")
    display_mutation = display.replace("73457681182843", "73457681182844", 1)
    require(display_mutation != display, "Self-test fixture did not change token-only wall icon")
    try:
        verify_sources(before_config, config, before_display, display_mutation, icon_ids)
    except VerificationError:
        rejected.append("unrelated_wall_icon_change")
    else:
        raise VerificationError("Self-test accepted unrelated wall icon change")
    after_catalog["catalogs"]["Products"]["Tokens20"]["TokenGrant"] = 21
    try:
        compare_catalogs(before_catalog, after_catalog, icon_ids)
    except VerificationError:
        rejected.append("evaluated_token_grant_change")
    else:
        raise VerificationError("Self-test accepted evaluated grant change")
    return {"passed": True, "synthetic_allowed_22_literal_replacements_accepted": True,
            "synthetic_evaluated_allowed_catalog_accepted": True,
            "prohibited_mutations_rejected": rejected, "negative_control_count": len(rejected),
            "note": "Synthetic verifier controls; not a Studio or gameplay test."}


def main() -> int:
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("--before-config", type=Path, default=AUDIT / "live-sources/ReplicatedStorage.ZyntraConfig.ModuleScript.luau")
    parser.add_argument("--before-display", type=Path, default=AUDIT / "live-sources/ServerScriptService.LobbyShopDisplay.ModuleScript.luau")
    parser.add_argument("--before-catalog", type=Path, default=AUDIT / "live-catalog.json")
    parser.add_argument("--after-config", type=Path)
    parser.add_argument("--after-display", type=Path)
    parser.add_argument("--published-mapping", type=Path)
    parser.add_argument("--after-catalog", type=Path)
    parser.add_argument("--report", type=Path)
    parser.add_argument("--self-test", action="store_true")
    args = parser.parse_args()
    try:
        before_config, before_display = read_source(args.before_config), read_source(args.before_display)
        if args.self_test:
            report = {"verifier_self_test": self_test(before_config, before_display,
                                                       json.loads(args.before_catalog.read_text()))}
        else:
            require(all((args.after_config, args.after_display, args.published_mapping)),
                    "--after-config, --after-display and --published-mapping are required")
            ids = mapping_ids(json.loads(args.published_mapping.read_text()))
            report = verify_sources(before_config, read_source(args.after_config), before_display,
                                    read_source(args.after_display), ids)
            report["evaluated_catalog"] = (compare_catalogs(json.loads(args.before_catalog.read_text()),
                                                            json.loads(args.after_catalog.read_text()), ids)
                                            if args.after_catalog else
                                            {"performed": False, "reason": "No evaluated after catalog supplied"})
        status = 0
    except (VerificationError, OSError, UnicodeError, json.JSONDecodeError) as error:
        report, status = {"passed": False, "error": str(error)}, 1
    encoded = json.dumps(report, indent=2, ensure_ascii=False) + "\n"
    if args.report:
        args.report.parent.mkdir(parents=True, exist_ok=True)
        args.report.write_text(encoded)
    print(encoded, end="")
    return status


if __name__ == "__main__":
    sys.exit(main())
