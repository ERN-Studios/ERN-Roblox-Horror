"""Read original Level 1 fixture image pixels through the owning Studio session.

No DataModel instances, scripts, assets or play state are changed.
python tools/level1_blender/export_fixture_reference.py --studio-id <exact id>
"""
from pathlib import Path
import argparse, base64, hashlib, json, sys
from PIL import Image

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--studio-id", required=True)
    args = parser.parse_args()
    target = ROOT / "assets/level1/blender-v2/concepts/original-fixtures"
    target.mkdir(parents=True, exist_ok=True)
    records = {}
    client = StudioMcpClient(find_mcp_batch())
    client.initialize()
    try:
        for name, aid in (("live", 135786374638992), ("dead", 107766152992499), ("original-wallpaper", 87947439437597)):
            setup = '''assert(game.PlaceId==131311258779917,"Wrong place")
local AS=game:GetService("AssetService")
local image=AS:CreateEditableImageAsync(Content.fromUri("rbxassetid://%d"))
assert(image,"Original image unavailable")
local size=image.Size
''' % aid
            code = setup + '''image:Destroy()
return game:GetService("HttpService"):JSONEncode({width=size.X,height=size.Y})'''
            response = client.call("execute_luau", {"studio_id": args.studio_id, "datamodel_type": "Edit", "code": code})
            size_data = json.loads(response)
            size = (size_data["width"], size_data["height"])
            pixels = bytearray()
            # Bounded rows avoid execute_luau's text cap on a full RGBA image.
            for row in range(0, size[1], 16):
                height = min(16, size[1] - row)
                code = setup + '''local pixels=image:ReadPixelsBuffer(Vector2.new(0,%d),Vector2.new(size.X,%d))
local encoded=game:GetService("EncodingService"):Base64Encode(pixels)
image:Destroy()
return game:GetService("HttpService"):JSONEncode({rgba=buffer.tostring(encoded)})''' % (row, height)
                response = client.call("execute_luau", {"studio_id": args.studio_id, "datamodel_type": "Edit", "code": code})
                try:
                    data = json.loads(response)
                except json.JSONDecodeError as error:
                    raise RuntimeError("Image strip result was truncated at %d characters" % len(response)) from error
                chunk = base64.b64decode(data["rgba"], validate=True)
                assert len(chunk) == size[0] * height * 4
                pixels.extend(chunk)
            assert len(pixels) == size[0] * size[1] * 4
            file = target / (name + ".png")
            if name == "original-wallpaper":
                file = ROOT / "assets/level1/blender-v2/textures/source/original-wallpaper.png"
                file.parent.mkdir(parents=True, exist_ok=True)
            Image.frombytes("RGBA", size, bytes(pixels)).save(file)
            records[name] = {"assetId": aid, "size": size, "sha256": hashlib.sha256(file.read_bytes()).hexdigest()}
            print(name, aid, size, flush=True)
    finally:
        client.close()
    (target / "source.json").write_text(json.dumps(records, indent=2), encoding="utf-8")


if __name__ == "__main__":
    main()
