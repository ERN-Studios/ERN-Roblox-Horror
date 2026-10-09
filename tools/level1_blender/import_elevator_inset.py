"""Upload/import only the separate Blender elevator kit; never overwrite existing art.

No flags writes a reviewable installer. --upload and --install require the exact
Studio ID. Texture receipts are hash checked; all prefab origins remain fixed.
"""
from pathlib import Path
import argparse
import hashlib
import importlib.util
import json
import sys

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/level1/elevator-inset-20261004"
EXPORT = ASSETS / "export"
KIT = "Level1ElevatorInsetKit"

spec = importlib.util.spec_from_file_location("level1_import_contract", Path(__file__).with_name("import_assets.py"))
base = importlib.util.module_from_spec(spec)
spec.loader.exec_module(base)
base.ASSETS, base.EXPORT, base.RESULTS = ASSETS, EXPORT, EXPORT / "roblox-assets.json"


def seed_wallpaper_receipts():
    original = ROOT / "assets/level1/blender-v2/textures/published.json"
    previous = json.loads(original.read_text(encoding="utf-8"))
    path = ASSETS / "textures/published.json"
    receipts = json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}
    for name in ("wallpaper_albedo.png", "wallpaper_normal.png", "wallpaper_rough.png"):
        actual = hashlib.sha256((ASSETS / "textures" / name).read_bytes()).hexdigest()
        receipt = previous[name]
        assert actual == receipt["sha256"], "Original wallpaper changed: " + name
        receipts[name] = {**receipt, "reusedFrom": "level1-blender-v2"}
    assert receipts["wallpaper_albedo.png"]["assetId"] == "rbxassetid://87947439437597"
    path.write_text(json.dumps(receipts, indent=2) + "\n", encoding="utf-8")


ASSEMBLIES = '''    for name, info in pairs(data.assemblies) do
        local model = Instance.new("Model"); model.Name = name; model.WorldPivot = CFrame.identity
        model:SetAttribute("SourceBuild", data.build)
        model:SetAttribute("FixedUV", true)
        model:SetAttribute("CabinWidth", info.width)
        model:SetAttribute("CabinDepth", info.depth)
        model:SetAttribute("CeilingY", info.ceilingY)
        for key, anchor in pairs(info.anchors) do model:SetAttribute(key, vec(anchor)) end
        for _, p in ipairs(info.placements) do
            local clone = assert(components:FindFirstChild(p.component)):Clone()
            clone.Name = p.component
            clone:SetAttribute("ElevatorRole", p.role)
            clone:PivotTo(cf(p.cf)); clone.Parent = model
        end
        model.WorldPivot = CFrame.identity; model.Parent = rooms
    end
'''


def installer(data):
    assert data["kitName"] == KIT and data["build"] == "level1-elevator-inset-20261004"
    assert set(data["assemblies"]) == {"CabinDepth" + str(d) for d in (12, 14, 16, 18)}
    assert not data["rooms"] and not data["aliases"]
    assert all(not c["colliders"] for c in data["components"].values())
    start = base.INSTALL.index("    for name, info in pairs(data.rooms) do")
    end = base.INSTALL.index("end)\nif not ok", start)
    code = base.INSTALL[:start] + ASSEMBLIES + base.INSTALL[end:]
    code = code.replace("Level1BlenderKit", KIT).replace('rooms.Name = "Rooms"', 'rooms.Name = "Assemblies"')
    code = code.replace('kit:SetAttribute("Ready", false)', '''kit:SetAttribute("Ready", false)
kit:SetAttribute("SteelTint", Color3.fromRGB(205, 211, 217))
for key, prop in pairs({albedo="SteelAlbedo", normal="SteelNormal", rough="SteelRough", metal="SteelMetal"}) do
    kit:SetAttribute(prop, assert(data.materials.InsetSteel.robloxMaps[key]))
end''')
    code = code.replace('kit:SetAttribute("Complete", true); kit:SetAttribute("Ready",true); kit.Parent = SS', '''-- A concurrent import must never be overwritten even if it finished while we yielded.
if SS:FindFirstChild("Level1ElevatorInsetKit") then kit:Destroy(); error("Concurrent elevator import: no overwrite") end
kit:SetAttribute("Complete", true); kit:SetAttribute("Ready",true); kit.Parent = SS''')
    code = code.replace('return "Level 1 Blender kit installed: "', 'return "Level 1 Blender elevator kit installed: "')
    code = code.replace(' .. " rooms"', ' .. " fixed cabin prefabs"')
    code = code.replace('s.Color = c.material == "Wallpaper" and Color3.fromRGB(table.unpack(style.color)) or Color3.new(1,1,1)',
        's.Color = c.material == "Wallpaper" and Color3.fromRGB(table.unpack(style.color)) or c.material == "InsetSteel" and kit:GetAttribute("SteelTint") or Color3.new(1,1,1)')
    payload = json.dumps(data, separators=(",", ":"))
    assert "]========]" not in payload
    code = code.replace("__PAYLOAD__", payload)
    (EXPORT / "install.luau").write_text(code, encoding="utf-8", newline="\n")
    return code


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--seed-wallpaper", action="store_true")
    parser.add_argument("--upload", action="store_true")
    parser.add_argument("--install", action="store_true")
    parser.add_argument("--studio-id")
    args = parser.parse_args()
    if args.seed_wallpaper:
        seed_wallpaper_receipts()
    data, records = base.payload()
    code = installer(data)
    if not (args.upload or args.install):
        print("Elevator installer prepared; no Studio writes.")
        return
    assert args.studio_id, "Exact Studio ID required"
    sys.path.insert(0, str(ROOT / "tools"))
    from sync_from_studio import StudioMcpClient, find_mcp_batch
    client = StudioMcpClient(find_mcp_batch())
    client.initialize()
    try:
        if args.upload:
            base.upload(client, args.studio_id, data, records)
            data, _ = base.payload()
            code = installer(data)
        if args.install:
            assert all(c["assetId"] for c in data["chunks"]), "Mesh uploads incomplete"
            response = client._request("tools/call", {"name": "execute_luau", "arguments": {
                "studio_id": args.studio_id, "datamodel_type": "Edit", "code": code}}, timeout=900)
            (EXPORT / "install-receipt.json").write_text(json.dumps(response, indent=2), encoding="utf-8")
            result = response.get("result", {})
            output = "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")
            assert not result.get("isError"), output
            print(output, flush=True)
    finally:
        client.close()


if __name__ == "__main__":
    main()
