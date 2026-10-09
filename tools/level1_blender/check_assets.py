"""One runnable check for the exported mesh, room/socket and PBR contract."""
from pathlib import Path
import argparse, base64, hashlib, json, math, struct

ROOT = Path(__file__).resolve().parents[2] / "assets/level1/blender"


def main():
    global ROOT
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=ROOT)
    ROOT = parser.parse_args().assets.resolve()
    d = json.loads((ROOT / "export/manifest.json").read_text())
    assert (d["cellSize"], d["wallHeight"], d["wallThickness"], d["floorTop"]) == (24, 14, 2, 0)
    assert len(d["chunks"]) <= 150 and len(d["rooms"]) >= 30
    for name in ("FloorPanel", "CeilingPanel", "LightFixture", "MetalPanel"):
        assert d["aliases"][name] in d["components"], name
    for name in ("Chair", "Table", "Telephone", "CardboardPile", "Printer", "GrandfatherClock"):
        assert name in d["components"], name
    for c in d["chunks"]:
        wire = (ROOT / "export/chunks" / ("c%05d.b64" % c["id"])).read_text().strip()
        blob = base64.b64decode(wire, validate=True)
        assert hashlib.sha256(blob).hexdigest() == c["sha256"]
        assert hashlib.sha256(wire.encode()).hexdigest() == c["wireSha256"]
        nv, nn, nu, nf = struct.unpack_from("<4I", blob)
        assert nf == c["tris"] <= 20000 and nv == c["verts"] <= 60000
        assert len(blob) == 16 + 12 * (nv + nn) + 8 * nu + 36 * nf
        values = struct.unpack_from("<%df" % (3 * (nv + nn) + 2 * nu), blob, 16)
        assert all(math.isfinite(v) for v in values)
        offset = 16 + 12 * (nv + nn) + 8 * nu
        faces = struct.unpack_from("<%dI" % (9 * nf), blob, offset)
        for i in range(0, len(faces), 3):
            assert faces[i] < nv and faces[i + 1] < nn and faces[i + 2] < nu
    masks = set()
    for name, room in d["rooms"].items():
        mask = room["mask"]; masks.add(mask)
        floor = [p for p in room["placements"] if p["role"] == "SurfaceFloor"]
        roof = [p for p in room["placements"] if p["role"] == "SurfaceCeiling"]
        walls = [p for p in room["placements"] if p["role"] == "ShellWalls"]
        assert len(floor) == len(roof) == 1, name
        assert len(walls) == 4 - mask.bit_count(), name
        for p in room["placements"]:
            assert p["component"] in d["components"] and len(p["cf"]) == 12
            x, y, z = p["cf"][:3]
            if p["component"] in ("Pillar", "WallShort"):
                # Transform the authored collision bounds, not just the model centre.
                for collider in d["components"][p["component"]]["colliders"]:
                    local = collider["cf"][:3]
                    rot = p["cf"][3:]
                    center = [p["cf"][i] + sum(rot[i * 3 + j] * local[j] for j in range(3)) for i in range(3)]
                    half = [sum(abs(rot[i * 3 + j]) * collider["size"][j] / 2 for j in range(3)) for i in range(3)]
                    xlo, xhi = center[0] - half[0], center[0] + half[0]
                    zlo, zhi = center[2] - half[2], center[2] + half[2]
                    assert xlo > 3 or xhi < -3, "detail enters north/south socket lane " + name
                    assert zlo > 3 or zhi < -3, "detail enters east/west socket lane " + name
                    assert xlo > 8 or xhi < -8 or zlo > 8 or zhi < -8, "detail enters central clear square " + name
        edges = {(0, 11.5): 1, (11.5, 0): 2, (0, -11.5): 4, (-11.5, 0): 8}
        for p in walls:
            x, _, z = p["cf"][:3]
            assert not mask & edges[(x, z)], "wall blocks open socket " + name
    assert masks == set(range(1, 16))
    for name in ("Carpet", "Wallpaper", "Ceiling"):
        assert set(d["materials"][name]["maps"]) == {"albedo", "normal", "rough"}
        for path in d["materials"][name]["maps"].values():
            assert (ROOT / "textures" / path).is_file()
    for material in d["materials"].values():
        assert all((ROOT / "textures" / filename).is_file() for filename in material["maps"].values())
    if d["version"] >= 2:
        required = ("RelayShell", "FuseBoxShell", "LeverShell", "ExitPortal", "ExitDoor", "RelayDoor",
                    "FuseSocket", "LeverShaft", "LeverKnob", "FuseCore", "FuseCap", "WallShort")
        assert all(name in d["components"] for name in required)
        assert d["fixture"]["banks"] == 5 and d["fixture"]["grid"] == [5, 5]
        assert d["wallpaperSourceAsset"] == 87947439437597
        exact = (ROOT / "textures/source/original-wallpaper.png").read_bytes()
        assert (ROOT / "textures/wallpaper_albedo.png").read_bytes() == exact
        published = json.loads((ROOT / "textures/published.json").read_text())
        receipt = published["wallpaper_albedo.png"]
        assert receipt["sha256"] == hashlib.sha256(exact).hexdigest()
        assert receipt["assetId"] == "rbxassetid://87947439437597"
        assert d["materials"]["Wallpaper"]["color"] == [255, 235, 150]
        assert d["materials"]["Wallpaper"]["tintTexture"]
        short_rooms = [room for room in d["rooms"].values() if room.get("shortWall")]
        assert len(short_rooms) == 8
        for room in d["rooms"].values():
            assert room["selectionWeight"] > 0
            assert all(p["component"] == "WallHalf" for p in room["placements"] if p["role"] == "ShellWalls")
            if room.get("shortWall"):
                assert room["shortWallHeight"] == 8.5
                dividers = [p for p in room["placements"] if p["component"] == "WallShort"]
                assert len(dividers) == 1 and dividers[0]["role"] == "Detail"
                assert d["components"]["WallShort"]["colliders"][0]["size"][1] == 8.5
    print("PASS: %d meshes, %d rooms; binary indices/hashes, all 15 socket masks, clear columns and PBR maps" %
          (len(d["chunks"]), len(d["rooms"])))


if __name__ == "__main__":
    main()
