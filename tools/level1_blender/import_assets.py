"""Upload/install ONLY the new Level 1 kit; explicit --upload or --install required.

python tools/level1_blender/import_assets.py                   # writes reviewable install.luau only
python tools/level1_blender/import_assets.py --upload --studio-id <exact id>
python tools/level1_blender/import_assets.py --install --studio-id <exact id>
Texture upload results belong in assets/level1/blender/textures/roblox-assets.json,
as {"carpet_albedo.png":"rbxassetid://123",...}. No existing kit is overwritten.
"""
from pathlib import Path
import argparse, hashlib, json, sys

ROOT = Path(__file__).resolve().parents[2]
ASSETS = ROOT / "assets/level1/blender"
EXPORT = ASSETS / "export"
RESULTS = EXPORT / "roblox-assets.json"
PLACE = 131311258779917
GROUP = 1039373905


def payload():
    manifest = json.loads((EXPORT / "manifest.json").read_text(encoding="utf-8"))
    records = json.loads(RESULTS.read_text()) if RESULTS.exists() else {}
    previous = ROOT / "assets/level1/blender/export/roblox-assets.json"
    if ASSETS.name == "blender-v2" and previous.exists():
        by_hash = {record["wireSha256"]: record for record in json.loads(previous.read_text()).values()}
        for chunk in manifest["chunks"]:
            old = by_hash.get(chunk["wireSha256"])
            if old and str(chunk["id"]) not in records:
                records[str(chunk["id"])] = {**old, "reusedFrom": "level1-blender-20261002"}
    mapsfile = ASSETS / "textures/roblox-assets.json"
    textures = json.loads(mapsfile.read_text()) if mapsfile.exists() else {}
    published = ASSETS / "textures/published.json"
    if published.exists():
        for name, receipt in json.loads(published.read_text()).items():
            path = ASSETS / "textures" / name
            if path.exists() and hashlib.sha256(path.read_bytes()).hexdigest() == receipt["sha256"]:
                textures[name] = receipt["assetId"]
    for c in manifest["chunks"]:
        rec = records.get(str(c["id"]))
        c["assetId"] = rec["assetId"] if rec and rec["wireSha256"] == c["wireSha256"] else None
    for m in manifest["materials"].values():
        m["robloxMaps"] = {k: textures.get(v) for k, v in m["maps"].items()}
    manifest["manifestSha256"] = hashlib.sha256((EXPORT / "manifest.json").read_bytes()).hexdigest()
    return manifest, records


INSTALL = '''
assert(game.PlaceId == 131311258779917, "Wrong place: Level 1 kit installation stopped")
local HS, AS = game:GetService("HttpService"), game:GetService("AssetService")
local SS = game:GetService("ServerStorage")
local data = HS:JSONDecode([========[__PAYLOAD__]========])
for _, c in ipairs(data.chunks) do assert(c.assetId, "Mesh not uploaded: " .. c.id) end
for name, m in pairs(data.materials) do
    for key in pairs(m.maps) do assert(m.robloxMaps[key], "Texture not uploaded: " .. name .. "/" .. key) end
end
assert(not SS:FindFirstChild("Level1BlenderKit"), "Existing Level1BlenderKit: inspect and reconcile; no overwrite")
local kit = Instance.new("Folder")
kit.Name = "Level1BlenderKit"
kit:SetAttribute("Build", data.build)
kit:SetAttribute("ManifestSha256", data.manifestSha256)
kit:SetAttribute("Complete", false)
kit:SetAttribute("Ready", false)
local components = Instance.new("Folder"); components.Name = "Components"; components.Parent = kit
local rooms = Instance.new("Folder"); rooms.Name = "Rooms"; rooms.Parent = kit
local function vec(a) return Vector3.new(a[1],a[2],a[3]) end
local function cf(a) return CFrame.new(table.unpack(a)) end
local byid = {}; for _,c in ipairs(data.chunks) do byid[c.id] = c end
local ok, err = pcall(function()
    for name, info in pairs(data.components) do
        local model = Instance.new("Model"); model.Name = name; model.WorldPivot = CFrame.identity
        model:SetAttribute("BlenderComponent", name); model:SetAttribute("SourceBuild", data.build)
        for _, id in ipairs(info.chunks) do
            local c, style = byid[id], data.materials[byid[id].material]
            local part = AS:CreateMeshPartAsync(Content.fromUri("rbxassetid://" .. c.assetId),
                {CollisionFidelity=Enum.CollisionFidelity.Box, RenderFidelity=Enum.RenderFidelity.Automatic})
            part.Name = c.material; part.Anchored = true; part.CanCollide = false
            part.CanTouch = false; part.CanQuery = false; part.CastShadow = true
            part.Size = vec(c.size); part.CFrame = CFrame.new(vec(c.center))
            part.Color = Color3.fromRGB(table.unpack(style.color)); part.Material = Enum.Material[style.robloxMaterial]
            part.Transparency = style.transparency or 0
            part:SetAttribute("BlenderChunk", id); part:SetAttribute("BlenderSourceSha256", c.sha256)
            part:SetAttribute("BlenderAssetId", c.assetId); part:SetAttribute("BlenderMaterial", c.material)
            if style.emission == 0 and next(style.maps) then
                local s = Instance.new("SurfaceAppearance"); s.Name = "BlenderPBR"
                for key, prop in pairs({albedo="ColorMap", normal="NormalMap", rough="RoughnessMap", metal="MetalnessMap"}) do
                    if style.robloxMaps[key] then s[prop] = style.robloxMaps[key] end
                end
                s.Color = c.material == "Wallpaper" and Color3.fromRGB(table.unpack(style.color)) or Color3.new(1,1,1)
                part.Color = Color3.new(1,1,1); s.Parent = part
            end
            part.Parent = model
        end
        -- Original maze floors, walls and ceilings remain the collision grid.
        -- Only additional Blender props/pillars need new simple Decor colliders.
        if name ~= "Floor" and name ~= "Ceiling" and name ~= "WallHalf" and #info.colliders > 0 then
            local folder = Instance.new("Folder"); folder.Name="Colliders"; folder.Parent=model
            for _, box in ipairs(info.colliders) do
                local part=Instance.new("Part"); part.Name="Collider"; part.Size=vec(box.size); part.CFrame=cf(box.cf)
                part.Anchored=true; part.Transparency=1; part.CanCollide=true; part.CanQuery=false; part.CanTouch=false
                part.CollisionGroup="Decor"; part:SetAttribute("RoomRole","Collider"); part.Parent=folder
            end
        end
        model.WorldPivot = CFrame.identity; model.Parent = components
    end
    for alias, original in pairs(data.aliases) do
        local clone = assert(components:FindFirstChild(original)):Clone(); clone.Name = alias; clone.Parent = components
    end
    for name, info in pairs(data.rooms) do
        local model = Instance.new("Model"); model.Name = name; model.WorldPivot = CFrame.identity
        model:SetAttribute("OpenMask", info.mask); model:SetAttribute("Variant", info.variant)
        model:SetAttribute("CellSize", info.cellSize); model:SetAttribute("SourceBuild", data.build)
        model:SetAttribute("SelectionWeight", info.selectionWeight or 1)
        model:SetAttribute("ShortWall", info.shortWall or false)
        if info.shortWallHeight then model:SetAttribute("ShortWallHeight", info.shortWallHeight) end
        for _, p in ipairs(info.placements) do
            local folder = model:FindFirstChild(p.role)
            if not folder then folder=Instance.new("Folder"); folder.Name=p.role; folder.Parent=model end
            local clone = assert(components:FindFirstChild(p.component)):Clone()
            for _, descendant in ipairs(clone:GetDescendants()) do
                if descendant:IsA("MeshPart") then descendant:SetAttribute("RoomRole",p.role) end
            end
            clone:PivotTo(cf(p.cf)); clone.Parent = folder
        end
        model.WorldPivot = CFrame.identity; model.Parent = rooms
    end
end)
if not ok then kit:Destroy(); error(err) end
kit:SetAttribute("Complete", true); kit:SetAttribute("Ready",true); kit.Parent = SS
return "Level 1 Blender kit installed: " .. #components:GetChildren() .. " components, " .. #rooms:GetChildren() .. " rooms"
'''


def write_installer(data, kit_name="Level1BlenderKit"):
    text = json.dumps(data, separators=(",", ":"))
    assert "]========]" not in text
    code = INSTALL.replace("__PAYLOAD__", text).replace("Level1BlenderKit", kit_name)
    (EXPORT / "install.luau").write_text(code, encoding="utf-8")
    return code


def upload(client, sid, data, records):
    helper = (ROOT / "tools/level4_blender/upload.luau").read_text(encoding="utf-8")
    helper = helper[helper.index("local function build(b)"):helper.index("local function run()")]
    pending = [c for c in data["chunks"] if not c["assetId"]]
    batch, size, batches = [], 0, []
    for c in pending:
        wire = (EXPORT / "chunks" / ("c%05d.b64" % c["id"])).read_text().strip()
        assert hashlib.sha256(wire.encode()).hexdigest() == c["wireSha256"]
        if batch and size + len(wire) > 650000:
            batches.append(batch); batch, size = [], 0
        batch.append((c, wire)); size += len(wire)
    if batch:
        batches.append(batch)
    for number, batch in enumerate(batches, 1):
        items = ",".join('{%d,"%s"}' % (c["id"], wire) for c, wire in batch)
        code = ('assert(game.PlaceId == %d,"Wrong place")\n' % PLACE +
                'local AS=game:GetService("AssetService"); local ENC=game:GetService("EncodingService")\n' + helper +
                'local out={}\nfor _,it in ipairs({' + items + '}) do\n' +
                'local ok,id=pcall(function()\nlocal em=build(ENC:Base64Decode(buffer.fromstring(it[2])))\n' +
                'local status,id=AS:CreateAssetAsync(em,Enum.AssetType.Mesh,{Name="L1_ModularKit_"..it[1],'
                'Description="Blender-built Level 1 yellow office kit",CreatorId=%d,CreatorType=Enum.AssetCreatorType.Group})\n' % GROUP +
                'em:Destroy(); assert(status==Enum.CreateAssetResult.Success,tostring(status))\n'
                'return id\nend)\ntable.insert(out,tostring(it[1]).."="..(ok and tostring(id) or "ERR:"..tostring(id)))\nend\nreturn table.concat(out,"\\n")')
        response = client._request("tools/call", {"name": "execute_luau", "arguments":
                                   {"studio_id": sid, "datamodel_type": "Edit", "code": code}}, timeout=900)
        result = response.get("result", {})
        text = "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")
        assert not result.get("isError"), text
        byid = {c["id"]: c for c, _ in batch}
        found = 0
        for line in text.splitlines():
            key, sep, value = line.partition("=")
            if sep and key.strip().isdigit() and value.strip().isdigit():
                cid = int(key)
                records[str(cid)] = {"assetId": int(value), "wireSha256": byid[cid]["wireSha256"], "group": GROUP}
                found += 1
        RESULTS.write_text(json.dumps(records, indent=2), encoding="utf-8")
        assert found == len(batch), "Incomplete upload result: " + text
        print("Uploaded batch %d/%d: %d meshes" % (number, len(batches), found), flush=True)


def main():
    global ASSETS, EXPORT, RESULTS
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("--upload", action="store_true")
    p.add_argument("--install", action="store_true")
    p.add_argument("--studio-id")
    p.add_argument("--assets", type=Path, default=ASSETS)
    p.add_argument("--kit-name", default="Level1BlenderKit")
    args = p.parse_args()
    ASSETS = args.assets.resolve()
    assert ASSETS.is_relative_to(ROOT / "assets/level1"), "Only Level 1 asset directories are supported"
    assert args.kit_name in ("Level1BlenderKit", "Level1BlenderKitV2"), "Explicit Level 1 kit name required"
    EXPORT = ASSETS / "export"
    RESULTS = EXPORT / "roblox-assets.json"
    data, records = payload()
    code = write_installer(data, args.kit_name)
    if not (args.upload or args.install):
        print("Reviewable installer written; %d/%d mesh assets present" % (sum(bool(c["assetId"]) for c in data["chunks"]), len(data["chunks"])))
        return
    assert args.studio_id, "Explicit exact --studio-id is required; no automatic session choice"
    sys.path.insert(0, str(ROOT / "tools"))
    import sync_from_studio as sync
    client = sync.StudioMcpClient(sync.find_mcp_batch())
    client.initialize()
    try:
        if args.upload:
            upload(client, args.studio_id, data, records)
            data, _ = payload(); code = write_installer(data, args.kit_name)
        if args.install:
            assert all(c["assetId"] for c in data["chunks"]), "Upload every mesh first"
            response = client._request("tools/call", {"name": "execute_luau", "arguments":
                                      {"studio_id": args.studio_id, "datamodel_type": "Edit", "code": code}}, timeout=900)
            result = response.get("result", {})
            text = "\n".join(b.get("text", "") for b in result.get("content", []) if b.get("type") == "text")
            assert not result.get("isError"), text
            print(text)
    finally:
        client.close()


if __name__ == "__main__":
    main()
