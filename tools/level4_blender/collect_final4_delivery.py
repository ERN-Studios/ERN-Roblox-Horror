"""Collect only the verified Cinema final4 delivery; preserve all external originals.

python tools/level4_blender/collect_final4_delivery.py --copy
No Studio, upload, Git staging, Blender save or backup action is performed.
"""
from pathlib import Path
import argparse, base64, hashlib, json, shutil

REPO = Path(__file__).resolve().parents[2]
SOURCE = Path("G:/Roblox/_local/l4facelift/v5")
TARGET = REPO / "assets/level4/cinema-final4"
LIMIT = 100_000_000


def sha(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--copy", action="store_true")
    args = parser.parse_args()
    record = json.loads((SOURCE / "final4/delivery_record.json").read_text())
    for source, expected in record["artifact_sha256"].items():
        assert sha(Path(source)) == expected, "Frozen delivery changed: " + source
    world = json.loads((SOURCE / "final4/export_studio/manifest.json").read_text())
    templates = json.loads((SOURCE / "assets/usher_export/manifest.json").read_text())
    results_path = REPO / "tools/level4_blender/results.jsonl"
    receipts = {row["id"]: row for row in map(json.loads, results_path.read_text().splitlines())}
    assert len(receipts) == 602
    selected = {}

    def select(source, relative, category):
        source = Path(source)
        destination = (TARGET / relative).resolve()
        assert destination.is_relative_to(TARGET.resolve()), relative
        assert source.is_file() and source.stat().st_size < LIMIT, source
        assert source.suffix not in (".log", ".pyc") and not source.name.endswith(".blend1"), source
        row = {"file": destination.relative_to(REPO).as_posix(), "source": str(source),
               "bytes": source.stat().st_size, "sha256": sha(source), "category": category}
        if destination in selected:
            assert selected[destination][1]["sha256"] == row["sha256"], relative
        selected[destination] = (source, row)

    select(SOURCE / "final4/final.blend", "world/Cinema_Final4.blend", "native")
    select(SOURCE / "assets/templates/templates.blend", "templates/Cinema_Templates.blend", "native")
    for source_dir, prefix, manifest in ((SOURCE / "final4/export_studio", "world/export", world),
                                        (SOURCE / "assets/usher_export", "templates/export", templates)):
        select(source_dir / "manifest.json", prefix + "/manifest.json", "manifest")
        for chunk in manifest["chunks"]:
            name = "c%05d.b64" % chunk["id"]
            source = source_dir / "chunks" / name
            wire = source.read_text().strip()
            base64.b64decode(wire, validate=True)
            assert hashlib.sha256(wire.encode()).hexdigest() == receipts[chunk["id"]]["h"], chunk["id"]
            select(source, prefix + "/chunks/" + name, "mesh")
    select(SOURCE / "final4/export_studio/chunks/c99999.b64", "world/export/chunks/c99999.b64", "placement-packet")
    # The raw export keeps all authoring markers; Studio filters the 5607 nav markers.
    select(SOURCE / "final4/export/manifest.json", "world/authoring-manifest.json", "manifest")
    select(SOURCE / "final4/export/chunks/c99999.b64", "world/authoring-placement-packet.b64", "placement-packet")
    select(results_path, "receipts/mesh-assets.jsonl", "receipt")
    select(REPO / "tools/level4_blender/textures.json", "receipts/world-texture-assets.json", "receipt")
    select(SOURCE / "assets/texture_ids.json", "receipts/template-texture-assets.json", "receipt")
    world_ids = json.loads((REPO / "tools/level4_blender/textures.json").read_text())
    maps = {mat[field] for mat in world["materials"].values()
            for field in ("tex", "normal", "rough", "metal") if mat.get(field)}
    assert len(maps) == 181 and maps <= set(world_ids)
    for filename in sorted(maps):
        source = next((folder / filename for folder in (
            Path("G:/Blender/Level4_Cinema/textures/pbr"), Path("G:/Blender/Level4_Cinema/textures"))
            if (folder / filename).is_file()), None)
        assert source, filename
        select(source, "world/textures/" + filename, "pbr")
    # This surviving native image datablock is outside the exporter material map.
    select(Path("G:/Blender/Level4_Cinema/textures/tex_marble_black_gold.png"),
           "world/textures/tex_marble_black_gold.png", "native-image")
    template_ids = json.loads((SOURCE / "assets/texture_ids.json").read_text())
    maps = {mat[field] for mat in templates["materials"].values()
            for field in ("tex", "normal", "rough", "metal") if mat.get(field)}
    assert len(maps) == 8 and maps == set(template_ids)
    for filename in sorted(maps):
        select(SOURCE / "assets/usher_export/textures" / filename,
               "templates/export/textures/" + filename, "pbr")
    for name in ("rig.json", "animations.json", "README.md"):
        select(SOURCE / "assets/usher_export" / name, "templates/export/" + name, "rig-animation")
    for name in ("build_templates.py", "build_templates.luau"):
        select(SOURCE / "assets" / name, "templates/" + name, "template-builder")
    for name in ("graph.json", "audit.json", "full_build_review.json", "visual_review.json"):
        select(SOURCE / "assets/nav" / name, "nav/" + name, "navigation")
    for name in ("delivery_record.json", "completion_checks.json", "contract_checks.json", "visual_review.json",
                 "HOLES.md", "DONE.txt", "render_input_hashes.json", "run.sh"):
        select(SOURCE / "final4" / name, "provenance/" + name, "offline-proof")
    for name in ("audit.json", "builder_check.json", "final_review.json", "artifact_hashes.json"):
        select(SOURCE / "assets/templates" / name, "provenance/templates-" + name, "offline-proof")
    select(SOURCE / "assets/markers/final_review.json", "provenance/markers-final-review.json", "offline-proof")
    select(SOURCE / "assets/source_record.json", "provenance/source-record.json", "offline-proof")
    select(SOURCE / "DESIGN.md", "provenance/DESIGN.md", "design")
    # Explicit final reviewer frames; no attempts, build logs or temporary harness state.
    for name in ("v4_gallery_1_east.png", "v4_gallery_3_ceiling.png", "v4_gallery_5_south.png",
                 "v4_booth_A1_interior.png", "v4_booth_A2_seats.png", "v4_booth_A3_window.png",
                 "v5_code_screen.png", "v5_exit_access.png", "v5_main_breaker.png", "v5_power_a.png",
                 "v5_power_b.png", "v5_prize_closed.png", "v5_spawn.png"):
        select(SOURCE / "final4/renders" / name, "qa/native/" + name, "native-review")
    for name in ("real_dark.jpg", "real_wave.jpg", "real_finale.jpg", "win.jpg", "escaped.jpg", "lobby_choice.jpg",
                 "trial_countdown.jpg", "preview_inside.jpg", "usher_real.jpg", "usher_flashlight.jpg", "usher_stun.jpg",
                 "death_card.jpg", "keypad_open.jpg", "cab_A.jpg", "cab_B.jpg"):
        select(SOURCE / "qa/shots" / name, "qa/previous-session/" + name, "previous-session-capture")
    total = sum(row["bytes"] for _, row in selected.values())
    if args.copy:
        TARGET.mkdir(parents=True, exist_ok=True)
        for destination, (source, row) in selected.items():
            destination.parent.mkdir(parents=True, exist_ok=True)
            if destination.exists():
                assert sha(destination) == row["sha256"], "Refusing to overwrite changed delivery: " + str(destination)
            else:
                shutil.copy2(source, destination)
            assert sha(destination) == row["sha256"]
        (TARGET / ".gitattributes").write_bytes(b"# Retain frozen asset/export/receipt bytes.\n* -text\n")
        inventory = {"purpose": "Exact manifest-selected copied delivery; no Studio or upload validation performed",
                     "source": str(SOURCE), "fileCount": len(selected), "totalBytes": total,
                     "largestFileBytes": max(row["bytes"] for _, row in selected.values()),
                     "individualFilesBelow100MB": True, "worldMeshReceipts": 570, "templateMeshReceipts": 32,
                     "worldPbrFiles": 181, "templatePbrFiles": 8,
                     "originalsPreserved": True, "nativePlaceBackupCreated": False,
                     "textureReceiptLimitation": "Existing texture IDs bind filenames; uploaded pixel hashes are not reported by those receipts",
                     "files": [row for _, row in sorted(selected.values(), key=lambda pair: pair[1]["file"])]}
        (TARGET / "delivery-inventory.json").write_text(json.dumps(inventory, indent=2), encoding="utf-8")
    print(json.dumps({"copied": args.copy, "files": len(selected), "totalMB": round(total / 1e6, 2),
                      "largestMB": round(max(row["bytes"] for _, row in selected.values()) / 1e6, 2),
                      "target": str(TARGET)}, indent=2))


if __name__ == "__main__":
    main()
