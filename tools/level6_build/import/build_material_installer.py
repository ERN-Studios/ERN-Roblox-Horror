"""Render a guarded, one-time Studio Edit material installer from uploaded IDs.

Pass a JSON object mapping either material-routes image keys or their repo-relative
source paths to numeric asset IDs (or rbxassetid:// IDs). This is local codegen;
the generated Luau must be run separately against a fresh, checked Studio state.
"""

from __future__ import annotations

import json
import re
import sys
from pathlib import Path


REPO = Path(__file__).resolve().parents[3]
DIR = REPO / "artifacts/level6-studio-revision-20261001/materials-studio"
ASSET_ID = re.compile(r"(?:rbxassetid://)?([1-9][0-9]*)$")


def main() -> None:
    assert len(sys.argv) == 2, "Usage: build_material_installer.py asset-ids.json"
    routes = json.loads((DIR / "material-routes.json").read_text())
    given = json.loads(Path(sys.argv[1]).read_text())
    assert isinstance(given, dict), "Expected an object of image key/path to asset ID"
    resolved = {}
    for image in routes["images"]:
        key = image["key"]
        path = image["source"]
        url_path = path.split("artifacts/level6-blender-revision-20260930/", 1)[-1]
        found = [given.get(candidate) for candidate in (key, path, url_path, f"http://127.0.0.1:8880/{url_path}")]
        values = {str(v) for v in found if v is not None}
        assert len(values) == 1, f"Missing or conflicting asset ID for {key}: {values}"
        match = ASSET_ID.fullmatch(values.pop())
        assert match, f"Invalid Roblox asset ID for {key}"
        resolved[key] = int(match.group(1))
    assert len(set(resolved.values())) == len(resolved), "Distinct source images unexpectedly share an asset ID"

    definitions = {}
    for key, variant in routes["variants"].items():
        definitions[key] = {
            "name": variant["name"],
            "base": variant["baseMaterial"],
            "tile": variant["studsPerTile"],
            "color": resolved[variant["mapImageKeys"]["color"]],
            "normal": resolved[variant["mapImageKeys"]["normalOpenGL"]],
            "roughness": resolved[variant["mapImageKeys"]["roughness"]],
            "metalness": resolved[variant["mapImageKeys"]["metalness"]] if "metalness" in variant["mapImageKeys"] else 0,
        }
    lines = [
        "-- Generated from verified Level 6 Blender PNG hashes. Studio Edit plugin context only.",
        "-- No global material override, existing object replacement, or gameplay source edit.",
        'local HS = game:GetService("HttpService")',
        'local MS = game:GetService("MaterialService")',
        'local RS = game:GetService("RunService")',
        'assert(not RS:IsRunning(), "Run only in Studio Edit mode")',
        'assert(game.PlaceId == 131311258779917 and game.GameId == 10559217407 and game.CreatorId == 1039373905, "Wrong target")',
        f'local expectedSource = "{routes["sourceMaterialManifestSha256"]}"',
        "local definitions = {",
    ]
    for key, d in definitions.items():
        lines.append(
            f'  {{key="{key}", name="{d["name"]}", base=Enum.Material.{d["base"]}, tile={d["tile"]}, '
            f'color="rbxassetid://{d["color"]}", normal="rbxassetid://{d["normal"]}", '
            f'roughness="rbxassetid://{d["roughness"]}", metalness="{f"rbxassetid://{d["metalness"]}" if d["metalness"] else ""}"}},'
        )
    lines += [
        "}",
        "local function matches(v, d)",
        "  return v:IsA(\"MaterialVariant\") and v.BaseMaterial == d.base and v.StudsPerTile == d.tile",
        "    and v.ColorMap == d.color and v.NormalMap == d.normal and v.RoughnessMap == d.roughness",
        "    and v.MetalnessMap == d.metalness and v:GetAttribute(\"Level6MaterialSourceSHA256\") == expectedSource",
        "end",
        "local created = {}",
        "for _, d in ipairs(definitions) do",
        "  local old = MS:FindFirstChild(d.name)",
        "  assert(old == nil or matches(old, d), \"Existing MaterialVariant conflicts: \" .. d.name)",
        "end",
        "local ok, err = pcall(function()",
        "  for _, d in ipairs(definitions) do",
        "    if not MS:FindFirstChild(d.name) then",
        "      local v = Instance.new(\"MaterialVariant\")",
        "      v.Name = d.name; v.BaseMaterial = d.base; v.StudsPerTile = d.tile",
        "      v.ColorMap = d.color; v.NormalMap = d.normal; v.RoughnessMap = d.roughness; v.MetalnessMap = d.metalness",
        "      v:SetAttribute(\"Level6MaterialSourceSHA256\", expectedSource)",
        "      assert(MS:FindFirstChild(d.name) == nil, \"MaterialVariant changed before write: \" .. d.name)",
        "      v.Parent = MS; table.insert(created, v)",
        "    end",
        "  end",
        "end)",
        "if not ok then for _, v in ipairs(created) do v:Destroy() end; error(err) end",
        "local report = {}",
        "for _, d in ipairs(definitions) do",
        "  local v = assert(MS:FindFirstChild(d.name)); assert(matches(v, d), \"Post-install mismatch: \" .. d.name)",
        "  table.insert(report, {name=d.name, base=tostring(v.BaseMaterial), tile=v.StudsPerTile,",
        "    color=v.ColorMap, normal=v.NormalMap, roughness=v.RoughnessMap, metalness=v.MetalnessMap})",
        "end",
        "return HS:JSONEncode({ok=true, created=#created, variants=report, sourceMaterialManifestSHA256=expectedSource})",
    ]
    path = DIR / "install_material_variants.generated.luau"
    path.write_text("\n".join(lines) + "\n")
    (DIR / "asset-ids.normalized.json").write_text(json.dumps(resolved, indent=2) + "\n")
    source_payload = {
        "schema": "level6-blender-materials/1",
        "sourceMaterialManifestSha256": routes["sourceMaterialManifestSha256"],
        "propsAtlasAssetId": resolved["props__color"],
        "variants": {
            key: {
                "name": d["name"],
                "baseMaterial": d["base"],
                "studsPerTile": d["tile"],
                "mapAssetIds": {role: resolved[image_key] for role, image_key in routes["variants"][key]["mapImageKeys"].items()},
            }
            for key, d in definitions.items()
        },
    }
    (DIR / "MaterialsJSON.json").write_text(json.dumps(source_payload, indent=2) + "\n")
    print(f"{path}: {len(definitions)} guarded variants, {len(resolved)} image IDs")


if __name__ == "__main__":
    main()
