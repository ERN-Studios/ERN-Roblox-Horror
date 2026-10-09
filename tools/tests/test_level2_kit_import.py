"""Execute the staged Level 2 kit installer in an offline Luau fake DataModel.

The plan runs locally; this test never opens a Studio session or uploads assets.
Set LUAU_BIN to the official Luau interpreter (luau-compile.exe beside it).
"""

from __future__ import annotations

import collections
import copy
import hashlib
import importlib.util
import json
import math
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile


ROOT = Path(__file__).resolve().parents[2]
EXPORT = ROOT / "assets/level2/blender-kit/export"
POOL_EXPORT = ROOT / "assets/level2/poolrooms-kit/export"
IMPORTER = ROOT / "tools/level2_blender/import_kit.py"
TEST_COMPONENTS = ("ChangingRoom_A", "Prop_bench", "DoorArch30", "StairFlight4", "SlideKit_1", "Column4_5_H34")
POOL_COMPONENTS = ("RoundTunnel_Wet_64", "CornerCove_R8_H34", "PumpStation",
                   "ExitTubeVisual", "ArrivalDoor")
POOL_VARIANTS = {"PR Tile", "PR Tile Aqua", "PR Iron"}   # FIX_SPEC G1: TileShade/Worn retired, one tile look; no mesh twins
POOL_TILE_RGB = [241, 237, 220]
POOL_TEMPLATE_FIXTURE = "PoolroomsTemplateFixture"


def luau_literal(value):
    if value is None:
        return "nil"
    if value is True:
        return "true"
    if value is False:
        return "false"
    if isinstance(value, str):
        return json.dumps(value, ensure_ascii=True)
    if isinstance(value, (int, float)):
        return repr(value)
    if isinstance(value, list):
        return "{" + ",".join(map(luau_literal, value)) + "}"
    if isinstance(value, dict):
        return "{" + ",".join(f"[{luau_literal(k)}]={luau_literal(v)}" for k, v in value.items()) + "}"
    raise TypeError(type(value))


FAKE_ENGINE = r'''
local mutationCount = 0
local readyMutation = nil
local createMeshCalls = 0
local instances = {}

local function makeEnum()
    return setmetatable({}, {__index = function(self, family)
        local values = setmetatable({}, {__index = function(_, name) return name end})
        rawset(self, family, values)
        return values
    end})
end
Enum = makeEnum()

Vector3 = {new = function(x, y, z) return {X=x, Y=y, Z=z, _datatype="Vector3"} end}
Vector2 = {new = function(x, y) return {X=x, Y=y, _datatype="Vector2"} end}
Color3 = {
    new = function(r, g, b) return {R=r, G=g, B=b, _datatype="Color3"} end,
    fromRGB = function(r, g, b) return {R=r/255, G=g/255, B=b/255, _datatype="Color3"} end,
}
local cfMeta
cfMeta = {__mul = function(a, b)
    return setmetatable({X=a.X+b.X, Y=a.Y+b.Y, Z=a.Z+b.Z, Yaw=a.Yaw+b.Yaw,
        Roll=(a.Roll or 0)+(b.Roll or 0), _datatype="CFrame"}, cfMeta)
end}
CFrame = {
    new = function(x, y, z)
        if type(x) == "table" then return setmetatable({X=x.X, Y=x.Y, Z=x.Z, Yaw=0, _datatype="CFrame"}, cfMeta) end
        return setmetatable({X=x or 0, Y=y or 0, Z=z or 0, Yaw=0, _datatype="CFrame"}, cfMeta)
    end,
    Angles = function(_, yaw, roll) return setmetatable({X=0, Y=0, Z=0,
        Yaw=yaw or 0, Roll=roll or 0, _datatype="CFrame"}, cfMeta) end,
    fromMatrix = function(position, right, up, back)
        return setmetatable({X=position.X, Y=position.Y, Z=position.Z, Yaw=0, _datatype="CFrame",
            RightVector=right, UpVector=up, BackVector=back, _fromMatrix=true}, cfMeta)
    end,
}
CFrame.identity = CFrame.new(0, 0, 0)
Content = {fromUri = function(uri) return uri end}
PhysicalProperties = {new = function(d, f, e, fw, ew)
    return {Density=d, Friction=f, Elasticity=e, FrictionWeight=fw, ElasticityWeight=ew, _datatype="PhysicalProperties"}
end}

local methods = {}
local instanceMeta = {}
function instanceMeta.__index(self, key)
    if methods[key] then return methods[key] end
    local property = self._props[key]
    if property ~= nil then return property end
    if self.ClassName == "MaterialVariant" and (key == "ColorMap" or key == "NormalMap"
        or key == "RoughnessMap" or key == "MetalnessMap") then return "" end
    for _, child in ipairs(self._children) do
        if child.Name == key then return child end
    end
    return nil
end
function instanceMeta.__newindex(self, key, value)
    if key == "Parent" then
        local old = self._props.Parent
        if old == value then return end
        if old then
            for i, child in ipairs(old._children) do
                if child == self then table.remove(old._children, i); break end
            end
        end
        self._props.Parent = value
        if value then table.insert(value._children, self) end
    else
        self._props[key] = value
    end
    mutationCount += 1
end
function methods:GetChildren()
    local out = {}
    for i, child in ipairs(self._children) do out[i] = child end
    return out
end
function methods:GetDescendants()
    local out = {}
    local function visit(node)
        for _, child in ipairs(node._children) do table.insert(out, child); visit(child) end
    end
    visit(self)
    return out
end
function methods:FindFirstChild(name, recursive)
    for _, child in ipairs(self._children) do
        if child.Name == name then return child end
    end
    if recursive then
        for _, child in ipairs(self._children) do
            local found = child:FindFirstChild(name, true)
            if found then return found end
        end
    end
    return nil
end
function methods:WaitForChild(name)
    return assert(self:FindFirstChild(name), "Missing child " .. tostring(name))
end
function methods:IsA(className)
    return self.ClassName == className or (className == "BasePart" and (self.ClassName == "Part" or self.ClassName == "MeshPart"))
end
function methods:SetAttribute(name, value)
    assert(type(value) ~= "table" or value._datatype, "Roblox attributes cannot hold a Lua table: " .. name)
    self._attrs[name] = value
    mutationCount += 1
    if name == "Ready" and value == true then
        assert(readyMutation == nil, "Ready set twice")
        readyMutation = mutationCount
    end
end
function methods:GetAttribute(name) return self._attrs[name] end
function methods:GetAttributes() return self._attrs end
function methods:Destroy()
    for _, child in ipairs(self:GetChildren()) do child:Destroy() end
    self.Parent = nil
    self._destroyed = true
end
function methods:PivotTo(cf) self.WorldPivot = cf end
function methods:GetFullName()
    if self.Parent then return self.Parent:GetFullName() .. "." .. self.Name end
    return self.Name
end
Instance = {}
function Instance.new(className, parent)
    local obj = setmetatable({ClassName=className, _props={Name=className}, _attrs={}, _children={}}, instanceMeta)
    table.insert(instances, obj)
    mutationCount += 1
    if parent then obj.Parent = parent end
    return obj
end

local services = {}
services.ServerStorage = Instance.new("ServerStorage")
services.MaterialService = Instance.new("MaterialService")
services.RunService = {IsRunning = function() return false end}
services.AssetService = {
    CreateMeshPartAsync = function(_, uri, options)
        assert(type(uri) == "string" and string.match(uri, "^rbxassetid://%d+$"), "bad mesh receipt URI")
        local mesh = Instance.new("MeshPart")
        mesh.MeshId = uri
        mesh.CollisionFidelity = options and options.CollisionFidelity
        mesh._creationFidelity = options and options.CollisionFidelity
        mesh.RenderFidelity = options and options.RenderFidelity
        mesh._creationRenderFidelity = options and options.RenderFidelity
        createMeshCalls += 1
        return mesh
    end,
    CreateAssetAsync = function(_, _asset, _kind, _config)
        return Enum.CreateAssetResult.Success, 900000000 + createMeshCalls
    end,
}
services.HttpService = {JSONDecode = function() error("plan payload unexpectedly needs HttpService JSONDecode") end}
game = {PlaceId=131311258779917, Name="BACKROOMS: Stay Quiet"}
function game:GetService(name) return assert(services[name], "unknown service " .. tostring(name)) end

local SS = services.ServerStorage
local MS = services.MaterialService
local keep = Instance.new("Folder"); keep.Name = "Unrelated"; keep.Parent = SS
local otherVariant = Instance.new("MaterialVariant"); otherVariant.Name = "Unrelated Variant"; otherVariant.Parent = MS
'''


CHECKS = r'''
local kit = assert(SS:FindFirstChild("Level2BlenderKit"), "kit not installed")
assert(kit.ClassName == "Folder", "kit class")
assert(kit:GetAttribute("Ready") == true, "kit not Ready")
assert(kit:GetAttribute("KitBuild") == expectedBuild, "KitBuild")
assert(kit:GetAttribute("ManifestSha256") == expectedManifestSha, "ManifestSha256")
assert(readyMutation == mutationCount, "Ready was not the last mutation")
assert(#SS:GetChildren() == 2 and SS:FindFirstChild("Unrelated") == keep, "ServerStorage root leak or unrelated object changed")
assert(MS:FindFirstChild("Unrelated Variant") == otherVariant, "unrelated MaterialVariant changed")
assert(#MS:GetChildren() == expectedVariantCount + 1, "MaterialService variant count")
for variantName, spec in pairs(expectedVariants) do
    local variant = assert(MS:FindFirstChild(variantName), "missing variant " .. variantName)
    assert(variant.ClassName == "MaterialVariant" and variant.BaseMaterial == "SmoothPlastic", variantName .. " class/base")
    assert(math.abs(variant.StudsPerTile - spec.tile_m / .28) < .0001, variantName .. " StudsPerTile")
    assert(variant.ColorMap and variant.NormalMap and variant.RoughnessMap, variantName .. " PBR maps")
    if spec.metal then assert(variant.MetalnessMap, variantName .. " metal map") end
end

local components = assert(kit:FindFirstChild("Components"), "Components missing")
local templates = assert(kit:FindFirstChild("SlideTemplates"), "SlideTemplates missing")
local data = assert(kit:FindFirstChild("Data"), "Data missing")
assert(components.ClassName == "Folder" and templates.ClassName == "Folder" and data.ClassName == "Folder", "kit folder classes")
assert(#components:GetChildren() == expectedComponentCount, "component count")
assert(#templates:GetChildren() == expectedTemplateCount, "slide template count")
for _, record in ipairs(expectedVerticalCylinders) do
    local model = assert(components:FindFirstChild(record[1]), "missing cylinder component " .. record[1])
    local part = assert(model:FindFirstChild(record[2]), "missing vertical cylinder " .. record[2])
    assert(part.Shape == "Cylinder" and part.CFrame and math.abs(math.deg(part.CFrame.Roll) - 90) < .0001,
        record[1] .. "." .. record[2] .. " vertical axis")
    assert(math.abs(part.Size.X - record[3]) < .0001 and
        math.abs(part.Size.Y - record[4]) < .0001 and
        math.abs(part.Size.Z - record[5]) < .0001,
        record[1] .. "." .. record[2] .. " native size")
end
for _, record in ipairs(expectedLongVisuals) do
    local model = assert(components:FindFirstChild(record[1]), "missing long slide visual " .. record[1])
    local part = assert(model:FindFirstChild(record[2]), "missing long slide mesh " .. record[2])
    assert(part._creationRenderFidelity == "Precise" and part.RenderFidelity == "Precise",
        record[2] .. " render fidelity at creation")
end

local function close(a, b) return math.abs(a-b) < 0.0001 end
local function checkColor(actual, rgb, context)
    assert(actual and close(actual.R, rgb[1]/255) and close(actual.G, rgb[2]/255)
        and close(actual.B, rgb[3]/255), context .. " color")
end
local function checkAttributes(node, attrs)
    for key, value in pairs(attrs) do
        if key == "Level2_SlideDirection" then
            local direction = node:GetAttribute(key)
            assert(direction and direction._datatype == "Vector3"
                and close(direction.X, value[1]) and close(direction.Y, value[2])
                and close(direction.Z, value[3]), node:GetFullName() .. " slide direction")
        elseif type(value) == "table" then
            assert(type(node:GetAttribute(key)) == "string", node:GetFullName() .. " complex attr " .. key .. " must be serialized")
        else
            assert(node:GetAttribute(key) == value, node:GetFullName() .. " attribute " .. key)
        end
    end
end
local function matchingChildren(parent, className)
    local out = {}
    for _, child in ipairs(parent:GetChildren()) do
        if child.ClassName == className then table.insert(out, child) end
    end
    return out
end
local function checkRecords(model, records, collider)
    local actual = matchingChildren(model, "Part")
    local used = {}
    for _, record in ipairs(records) do
        local found = nil
        for i, part in ipairs(actual) do
            if not used[i] and part.Name == record.name then found = i; break end
        end
        assert(found, model.Name .. " missing Part " .. record.name)
        used[found] = true
        local part = actual[found]
        assert(part.Anchored == true, part.Name .. " not anchored")
        local size = record.size
        if collider and record.shape == "Cylinder" then
            size = {record.attrs.NativeSizeX, record.attrs.NativeSizeY, record.attrs.NativeSizeZ}
            assert(close(math.deg(part.CFrame.Roll), record.attrs.NativeRotationZ), part.Name .. " cylinder axis")
        end
        assert(part.Size and close(part.Size.X, size[1]) and close(part.Size.Y, size[2])
            and close(part.Size.Z, size[3]), part.Name .. " size")
        assert(part.CFrame and close(part.CFrame.X, record.cf[1]) and close(part.CFrame.Y, record.cf[2])
            and close(part.CFrame.Z, record.cf[3]), part.Name .. " CFrame")
        assert(part.CanCollide == (collider or record.collide), part.Name .. " CanCollide")
        assert(part.CanQuery == (collider or record.collide), part.Name .. " CanQuery")
        if collider then
            assert(part.Transparency == 1 and part.CanTouch == false, part.Name .. " collider flags")
            assert(part.Shape == record.shape, part.Name .. " shape")
        else
            assert(part.Material == "SmoothPlastic", part.Name .. " material")
            assert(part.MaterialVariant == (expectedMaterials[record.material].variant or ""), part.Name .. " variant")
            checkColor(part.Color, record.properties and record.properties.Color or expectedMaterials[record.material].color, part.Name)
        end
        if record.ground then assert(part:GetAttribute("Level2_EntityGround") == true, part.Name .. " ground attr") end
        checkAttributes(part, record.attrs)
    end
end
for componentName, spec in pairs(expectedComponents) do
    local model = assert(components:FindFirstChild(componentName), "missing component " .. componentName)
    assert(model.ClassName == "Model", componentName .. " class")
    assert(model.WorldPivot and close(model.WorldPivot.X, 0) and close(model.WorldPivot.Y, 0)
        and close(model.WorldPivot.Z, 0), componentName .. " origin pivot")
    checkAttributes(model, spec.attrs)
    local markers = assert(model:FindFirstChild("Markers"), componentName .. " Markers folder")
    assert(markers.ClassName == "Folder", componentName .. " Markers class")
    local actualMarkers = markers:GetChildren()
    assert(#actualMarkers == #spec.markers, componentName .. " marker count")
    local usedMarkers = {}
    for _, expected in ipairs(spec.markers) do
        local found = nil
        for i, marker in ipairs(actualMarkers) do
            local cf = marker.Value
            if not usedMarkers[i] and marker.Name == expected.name and marker.ClassName == "CFrameValue"
                and cf and close(cf.X, expected.cf[1]) and close(cf.Y, expected.cf[2])
                and close(cf.Z, expected.cf[3]) and close(math.deg(cf.Yaw), expected.cf[4]) then
                found = i; break
            end
        end
        assert(found, componentName .. " missing CFrameValue marker " .. expected.name)
        usedMarkers[found] = true
        checkAttributes(actualMarkers[found], expected.attrs)
    end
    local meshes = matchingChildren(model, "MeshPart")
    assert(#meshes == #spec.chunks, componentName .. " mesh count")
    local foundMeshNames = {}
    for _, mesh in ipairs(meshes) do
        assert(mesh.Anchored == true and mesh.CanCollide == false and mesh.CanQuery == false and mesh.CanTouch == false,
            componentName .. " visual MeshPart flags")
        assert(mesh._creationFidelity == "Box", componentName .. " visual mesh creation fidelity")
        foundMeshNames[mesh.Name] = (foundMeshNames[mesh.Name] or 0) + 1
    end
    for _, chunk in ipairs(spec.expectedMeshes) do
        local name = componentName .. "_" .. chunk.material
        assert((foundMeshNames[name] or 0) > 0, componentName .. " missing mesh " .. name)
        foundMeshNames[name] -= 1
        local mesh = assert(model:FindFirstChild(name))
        local material = expectedMaterials[chunk.material]
        assert(mesh.Material == material.robloxMaterial, name .. " base material")
        checkColor(mesh.Color, material.color, name)
        assert(mesh.Size and close(mesh.Size.X, chunk.size[1]) and close(mesh.Size.Y, chunk.size[2])
            and close(mesh.Size.Z, chunk.size[3]), name .. " size")
        assert(mesh.CFrame and close(mesh.CFrame.X, chunk.center[1]) and close(mesh.CFrame.Y, chunk.center[2])
            and close(mesh.CFrame.Z, chunk.center[3]), name .. " CFrame")
        assert(mesh.CastShadow == (math.max(table.unpack(chunk.size)) > 8), name .. " CastShadow")
        if material.tileSurface then
            -- Tile meshes wear the variant's maps as ONE SurfaceAppearance (UV-true grout), never the variant itself.
            local sa = mesh:FindFirstChild("Tile")
            assert(sa and sa.ClassName == "SurfaceAppearance", name .. " tile SurfaceAppearance")
            assert(#mesh:GetChildren() == 1, name .. " exactly one SurfaceAppearance")
            assert(sa.ColorMap and sa.NormalMap and sa.RoughnessMap, name .. " tile maps")
            checkColor(sa.Color, material.color, name .. " tile tint")
            assert(mesh.MaterialVariant == "", name .. " tile mesh must not wear a MaterialVariant")
        elseif material.atlas then
            assert(mesh:FindFirstChild("Atlas"), name .. " atlas appearance")
        elseif material.variant then
            assert(mesh.MaterialVariant == material.variant, name .. " variant")
        end
    end
    for name, count in pairs(foundMeshNames) do
        assert(count == 0, componentName .. " unexpected mesh " .. name)
    end
    checkRecords(model, spec.parts, false)
    -- Both authored Parts and collider records are Part children. Separate the
    -- record sets by matching the full, ordered name multiset below.
    local allParts = matchingChildren(model, "Part")
    assert(#allParts == #spec.parts + #spec.colliders, componentName .. " total Part count")
    checkRecords(model, spec.colliders, true)
    local names = {}
    for _, part in ipairs(allParts) do names[part.Name] = (names[part.Name] or 0) + 1 end
    for _, record in ipairs(spec.parts) do names[record.name] -= 1 end
    for _, record in ipairs(spec.colliders) do names[record.name] -= 1 end
    for name, count in pairs(names) do assert(count == 0, componentName .. " unexpected Part " .. name) end
end

if expectedProfile == "c" then
local prop = assert(components:FindFirstChild("Prop_bench"))
local atlasMesh = assert(matchingChildren(prop, "MeshPart")[1], "atlas prop mesh")
local atlas = assert(atlasMesh:FindFirstChild("Atlas"), "atlas SurfaceAppearance")
assert(atlas.ClassName == "SurfaceAppearance", "atlas class")
assert(atlas.ColorMap and atlas.NormalMap and atlas.RoughnessMap and atlas.MetalnessMap, "atlas maps")
assert(atlasMesh.MaterialVariant == nil or atlasMesh.MaterialVariant == "", "atlas prop should use SurfaceAppearance")
end

for _, name in ipairs(expectedPoolTemplates) do
    -- A Poolrooms component with Template=true is a SlideTemplates collision MeshPart, never a Component.
    local part = assert(templates:FindFirstChild(name), "missing Poolrooms slide template " .. name)
    assert(components:FindFirstChild(name) == nil, name .. " was also installed as a Component")
    assert(part.ClassName == "MeshPart" and part._creationFidelity == "PreciseConvexDecomposition"
        and part.CollisionFidelity == "PreciseConvexDecomposition", name .. " template collision fidelity")
    assert(part.Anchored and part.Transparency == 1 and part.CanCollide and part.CanQuery and not part.CanTouch
        and part.CastShadow == false and part.MaterialVariant == "", name .. " template flags")
    assert(part:GetAttribute("WireSha256") and part:GetAttribute("AssetId"), name .. " template receipt attributes")
end

local floorTemplate = assert(templates:FindFirstChild("SlideCol_Floor_r7.5"), "slide collision floor template")
assert(floorTemplate.ClassName == "MeshPart", "slide template class")
assert(floorTemplate._creationFidelity == "PreciseConvexDecomposition", "slide fidelity must be specified at creation")
assert(floorTemplate.CollisionFidelity == "PreciseConvexDecomposition", "slide fidelity")
assert(floorTemplate.Anchored and floorTemplate.CanCollide and floorTemplate.CanQuery and not floorTemplate.CanTouch,
    "slide collision flags")
assert(floorTemplate.Transparency == 1, "slide invisible")
local physics = assert(floorTemplate.CustomPhysicalProperties, "slide physical properties")
assert(close(physics.Density, .7) and close(physics.Friction, .05) and close(physics.Elasticity, .05)
    and close(physics.FrictionWeight, 1) and close(physics.ElasticityWeight, 1), "slide physical properties values")

if expectedProfile == "c" then
local slideKit = assert(components:FindFirstChild("SlideKit_1"), "slide entry component")
local entry = assert(slideKit:FindFirstChild(expectedSlideEntry.name), "slide entry Part")
assert(entry.ClassName == "Part" and entry.CFrame and entry.CFrame._fromMatrix, "slide entry full CFrame")
for _, axis in ipairs({{"RightVector", "right"}, {"UpVector", "up"}, {"BackVector", "back"}}) do
    local actual = assert(entry.CFrame[axis[1]], "slide entry missing " .. axis[1])
    local expected = expectedSlideEntry.cframe[axis[2]]
    assert(close(actual.X, expected[1]) and close(actual.Y, expected[2])
        and close(actual.Z, expected[3]), "slide entry " .. axis[1])
end
assert(entry.Transparency == 1 and entry.CanCollide and entry.CanQuery and not entry.CanTouch
    and entry.CastShadow == false and entry.CollisionGroup == "Default", "slide entry collision override")
assert(entry.CollisionFidelity == nil, "Part received MeshPart-only CollisionFidelity")
local entryPhysics = assert(entry.CustomPhysicalProperties, "slide entry physical override")
assert(close(entryPhysics.Density, .7) and close(entryPhysics.Friction, .05)
    and close(entryPhysics.Elasticity, .05) and close(entryPhysics.FrictionWeight, 1)
    and close(entryPhysics.ElasticityWeight, 1), "slide entry physical override values")
end

local textParts = data:GetChildren()
assert(#textParts > 0, "SlidesJSON missing")
table.sort(textParts, function(a, b) return a.Name < b.Name end)
local strings = {}
for i, node in ipairs(textParts) do
    assert(node.ClassName == "StringValue" and node.Name == string.format("SlidesJSON-%03d", i), "SlidesJSON names/classes")
    assert(#node.Value <= 190000, "SlidesJSON fragment too large")
    strings[i] = node.Value
end
print("SLIDES_JSON_BEGIN")
print(table.concat(strings))
print("SLIDES_JSON_END")
print("KIT_IMPORT_FAKE_OK " .. tostring(createMeshCalls))
'''


# Planted negatives for the read-only audit (Poolrooms): it must refuse a tile MeshPart without its SurfaceAppearance,
# with a wrong ColorMap, wearing the tile MaterialVariant, or with a second SurfaceAppearance; and pass once restored.
AUDIT_NEGATIVES = r"""
local victim
for _, d in ipairs(components:GetDescendants()) do
    if d.ClassName == "MeshPart" and d:FindFirstChild("Tile") then victim = d; break end
end
assert(victim, "no tile MeshPart to plant audit negatives on")
local sa = victim:FindFirstChild("Tile")
local function refused(label, pattern)
    local ok, err = pcall(auditPhase)
    assert(not ok and string.find(tostring(err), pattern, 1, true), "audit accepted " .. label .. ": " .. tostring(err))
end
sa.Parent = nil
refused("a tile MeshPart without its SurfaceAppearance", "Want exactly one SurfaceAppearance")
sa.Parent = victim
local goodMap = sa.ColorMap
sa.ColorMap = "rbxassetid://1"
refused("a wrong ColorMap", "SurfaceAppearance receipt mismatch")
sa.ColorMap = goodMap
victim.MaterialVariant = "PR Tile"
refused("a tile MeshPart wearing PR Tile", "Mesh MaterialVariant mismatch")
victim.MaterialVariant = ""
local extra = Instance.new("SurfaceAppearance"); extra.Name = "Tile"; extra.Parent = victim
refused("a second SurfaceAppearance", "Want exactly one SurfaceAppearance")
extra.Parent = nil
assert(string.find(auditPhase(), "AUDIT OK", 1, true) == 1, "audit fails once the planted negatives are restored")
print("AUDIT_NEGATIVES_OK 4")
"""


def make_checks(manifest, data, profile, pool_templates=()):
    by_id = {chunk["id"]: chunk for chunk in manifest["chunks"]}
    selected = {
        name: {
            **manifest["components"][name],
            "expectedMeshes": [by_id[chunk_id] for chunk_id in manifest["components"][name]["chunks"]],
        }
        for name in (POOL_COMPONENTS if profile == "poolrooms" else TEST_COMPONENTS)
    }
    template_count = sum(len(c["chunks"]) for c in manifest["components"].values() if c["attrs"].get("Template"))
    component_count = len(manifest["components"])
    material_data = {
        name: {
            "variant": m.get("variant"), "color": m["color"],
            "robloxMaterial": m["robloxMaterial"], "atlas": bool(m.get("atlas")),
            "tileSurface": profile == "poolrooms" and m.get("variant") in ("PR Tile", "PR Tile Aqua"),
        }
        for name, m in manifest["materials"].items()
    }
    variants = {}
    pbr_root = Path(r"G:/Blender/Level2_Pool/textures/pbr")
    for material in manifest["materials"].values():
        if material.get("variant") and material.get("pbr"):
            variants[material["variant"]] = {
                "tile_m": material["tile_m"],
                "metal": (pbr_root / f"{material['pbr']}_metal.png").exists(),
            }
    values = {
        "expectedProfile": profile,
        "expectedPoolTemplates": sorted(pool_templates),
        "expectedBuild": manifest["build"],
        "expectedManifestSha": data["manifest_sha"],
        "expectedComponents": selected,
        "expectedMaterials": material_data,
        "expectedVariants": variants,
        "expectedVariantCount": len(variants),
        "expectedComponentCount": (sum(not info["attrs"].get("Template")
                                       for info in manifest["components"].values())
                                   if profile == "poolrooms" else component_count),
        "expectedTemplateCount": template_count,
        "expectedVerticalCylinders": [
            [name, record["name"], record["size"][1], record["size"][0], record["size"][2]]
            for name, component in manifest["components"].items()
            for record in component["colliders"]
            if record["shape"] == "Cylinder" and record["attrs"].get("CylinderAxis") == "Y"
        ],
        "expectedLongVisuals": [
            [name, name + "_" + by_id[i]["material"]] for name, component in manifest["components"].items()
            if (component["attrs"].get("Level2_SlideVisual") or
                component["attrs"].get("Role") == "ExitFlumeVisual")
            for i in component["chunks"] if max(by_id[i]["size"]) > 100
        ],
        "expectedSlideEntry": (next(part for part in manifest["components"]["SlideKit_1"]["parts"]
                                    if part.get("cframe")) if profile == "c" else None),
    }
    return "\n".join(f"local {key} = {luau_literal(value)}" for key, value in values.items()) + "\n" + CHECKS


def phase_function(path, label):
    source = path.read_text(encoding="utf-8")
    return f"local function {label}()\n{source}\nend\n{label}()\n"


def overwrite_check(init_path):
    source = init_path.read_text(encoding="utf-8")
    return (
        "local beforeOverwrite = mutationCount\n"
        "local overwriteOk = pcall(function()\n"
        + source
        + "\nend)\n"
        "assert(not overwriteOk, 'existing kit overwrite was accepted')\n"
        "assert(mutationCount == beforeOverwrite, 'overwrite refusal mutated the tree')\n"
    )


def run_luau(luau, source, staging, name):
    runner = staging / name
    runner.write_text(source, encoding="utf-8")
    return subprocess.run([str(luau), str(runner)], capture_output=True, text=True, encoding="utf-8")


def check_geometry(manifest):
    components = manifest["components"]
    tunnels = {name: info for name, info in components.items() if name.startswith("Tunnel_")}
    assert tunnels, "no exported tunnels"
    for name, info in tunnels.items():
        length = info["attrs"]["length"]
        for side in (-1, 1):
            backstops = [r for r in info["colliders"]
                         if r["name"] == f"Level 2 Corridor Shell Backstop {side:+}"]
            assert len(backstops) == 1, f"{name}: missing side {side} backstop"
            record = backstops[0]
            x, y, z, yaw = record["cf"]
            width, height, span = record["size"]
            assert yaw == 0 and abs(z) < .0001 and span >= length - .0001, f"{name}: broken full-length side"
            inner = abs(x) - width / 2
            assert 15 <= inner <= 15.25 and abs(x) + width / 2 >= 17, f"{name}: mouth or edge exposed"
            assert y - height / 2 <= -3 and y + height / 2 >= 30, f"{name}: side height exposed"
            assert not record["ground"] and record["shape"] == "Block", f"{name}: side collider flags"
    cylinders = [(name, r) for name, info in components.items() for r in info["colliders"]
                 if r["shape"] == "Cylinder"]
    assert len(cylinders) >= 13 and all(r["attrs"].get("CylinderAxis") == "Y" for _, r in cylinders), \
        "an exported Cylinder lacks its vertical axis"
    for name in ("SlideHall", "GrandSlideHall"):
        assert {r["name"] for n, r in cylinders if n == name} == {"L2K Helix Core", "L2K Spiral Core"}
    source = (ROOT / "tools/level2_blender/kit.py").read_text(encoding="utf-8")
    assert source.count('Matrix.Rotation(math.radians(yaw), 4, "Z")') == 2, "preview yaw disagrees with builder"
    builder = (ROOT / "ServerScriptService/Level 2 Systems/Level 2 Kit World Builder.ModuleScript.lua").read_text(
        encoding="utf-8")
    assert 'CFrame.Angles(0,math.rad(yaw),0)' in builder, "builder yaw convention changed"
    # Exported cf yaw is Roblox degrees. Blender=(x,-z,y); applying the
    # preview's +Z rotation yields the same x,z as Roblox's +Y rotation.
    yaws = {r["cf"][3] for info in components.values()
            for r in info["parts"] + info["colliders"] if len(r["cf"]) == 4}
    assert 90 in yaws and -90 in yaws, "missing directional yaw fixtures"
    for yaw in yaws:
        angle = math.radians(yaw)
        x, z = 2.3, -4.7
        roblox = (math.cos(angle) * x + math.sin(angle) * z,
                  -math.sin(angle) * x + math.cos(angle) * z)
        blender = (math.cos(angle) * x - math.sin(angle) * -z,
                   math.sin(angle) * x + math.cos(angle) * -z)
        assert all(abs(a - b) < 1e-10 for a, b in zip(blender, (roblox[0], -roblox[1]))), \
            f"preview/export yaw mismatch at {yaw} degrees"


def make_pool_fixture(dst):
    """The canonical Poolrooms export brought to the G1 palette (retired TileShade/Worn chunks dropped, their Part
    records retargeted to Tile, tile colours = TILE_RGB) plus one synthetic Template component, so the installer's
    Poolrooms template path is exercised independent of a kit rebuild. Written only under the test's temp dir."""
    src = json.loads((POOL_EXPORT / "manifest.json").read_text(encoding="utf-8"))
    retired = {"TileShade", "Worn"}
    keep = [c for c in src["chunks"] if c["material"] not in retired]
    remap = {c["id"]: i for i, c in enumerate(keep)}
    (dst / "chunks").mkdir(parents=True)
    chunks = []
    for c in keep:
        shutil.copyfile(POOL_EXPORT / "chunks" / f"c{c['id']:05d}.b64", dst / "chunks" / f"c{remap[c['id']]:05d}.b64")
        chunks.append({**c, "id": remap[c["id"]]})
    materials = {k: dict(v) for k, v in src["materials"].items() if k not in retired}
    for material in materials.values():
        if material.get("variant") in ("PR Tile", "PR Tile Aqua"):
            material["color"] = POOL_TILE_RGB
    components = {}
    for name, info in src["components"].items():
        info = copy.deepcopy(info)
        info["chunks"] = [remap[i] for i in info["chunks"] if i in remap]
        for record in info["parts"]:
            if record["material"] in retired:
                record["material"] = "Tile"
        components[name] = info
    donor = min((c for c in chunks if c["material"] == "Tile"), key=lambda c: c["tris"])
    template_id = len(chunks)
    shutil.copyfile(dst / "chunks" / f"c{donor['id']:05d}.b64", dst / "chunks" / f"c{template_id:05d}.b64")
    chunks.append({**donor, "id": template_id, "component": POOL_TEMPLATE_FIXTURE})
    components[POOL_TEMPLATE_FIXTURE] = {"attrs": {"Template": True, "Role": "PoolroomsTemplateFixture"},
                                         "parts": [], "colliders": [], "markers": [], "chunks": [template_id]}
    manifest = {**src, "materials": materials, "components": components, "chunks": chunks}
    (dst / "manifest.json").write_text(json.dumps(manifest, indent=1), encoding="utf-8")
    return manifest


def check_pool_guards(importer, export):
    """validate_export refuses a stale palette and a Template component the installer would truncate."""
    path = export / "manifest.json"
    original = path.read_text(encoding="utf-8")
    good = json.loads(original)
    worn = copy.deepcopy(good)
    worn["materials"]["Worn"] = {**good["materials"]["Aqua"], "variant": "PR Tile Worn", "pbr": "pr_worn"}
    white = copy.deepcopy(good)
    white["materials"]["Tile"]["color"] = [255, 255, 255]
    records = copy.deepcopy(good)
    records["components"][POOL_TEMPLATE_FIXTURE]["colliders"] = [
        {"name": "Lost", "cf": [0, 0, 0, 0], "size": [1, 1, 1], "ground": False, "shape": "Block", "attrs": {}}]
    two = copy.deepcopy(good)
    other_chunk = next(c for c in two["chunks"] if c["material"] != "Tile")
    two["components"][other_chunk["component"]]["chunks"].remove(other_chunk["id"])
    other_chunk["component"] = POOL_TEMPLATE_FIXTURE
    two["components"][POOL_TEMPLATE_FIXTURE]["chunks"].append(other_chunk["id"])
    try:
        for label, mutated in (("retired Worn material", worn), ("255 tile colour", white),
                               ("template with a collider", records), ("template with two chunks", two)):
            path.write_text(json.dumps(mutated), encoding="utf-8")
            try:
                importer.validate_export(export, "poolrooms")
            except ValueError:
                pass
            else:
                raise AssertionError(f"poolrooms validate_export accepted a {label}")
    finally:
        path.write_text(original, encoding="utf-8")


def run_profile(profile, luau, pool_fixture=False):
    with tempfile.TemporaryDirectory(prefix=".test_kit_import_", dir=ROOT / "tools/level2_blender") as temp:
        base = Path(temp)
        staging = base / "payloads"
        sys.dont_write_bytecode = True
        spec = importlib.util.spec_from_file_location("level2_kit_import_for_test", IMPORTER)
        assert spec and spec.loader
        importer = importlib.util.module_from_spec(spec)
        spec.loader.exec_module(importer)
        pool_export = POOL_EXPORT
        if pool_fixture:
            pool_export = base / "pool_fixture_export"
            make_pool_fixture(pool_export)
            importer.POOL_EXPORT = pool_export
            check_pool_guards(importer, pool_export)
        data = importer.validate_export(pool_export if profile == "poolrooms" else EXPORT, profile)
        manifest = data["manifest"]
        slides = data["slides"]
        if profile == "c":
            check_geometry(manifest)
        else:
            # The 53 reviewed style-C slide templates plus the Poolrooms exit-bore templates.
            pool_templates = [name for name, item in json.loads((pool_export / "manifest.json").read_text())[
                "components"].items() if name.startswith("SlideCol_") and item.get("attrs", {}).get("Template")]
            assert len([name for name in manifest["components"] if name.startswith("SlideCol_")]) \
                == 53 + len(pool_templates)
        importer.texture_sources(data)
        if profile == "poolrooms":
            assert set(data["variants"]) == POOL_VARIANTS
            # LATTICE_SPEC 2.1: 0.5-stud tiles, 8 x 8 per texture -> StudsPerTile 4.0 for both tile variants.
            assert all(abs(data["variants"][v]["tile_m"] / .28 - 4.0) < 1e-9 for v in ("PR Tile", "PR Tile Aqua"))
            # Kit tile meshes take the tile variant's own maps through a SurfaceAppearance; the retired mesh twins
            # (a MaterialVariant ignores mesh UVs) and their StudsPerTile constant are gone.
            assert not hasattr(importer, "MESH_STUDS_PER_TILE")
            for name, material in manifest["materials"].items():
                if material.get("variant") in ("PR Tile", "PR Tile Aqua"):
                    assert data["atlas_maps"][name] == data["variants"][material["variant"]]["maps"], name
            assert not any(v.startswith("L2K ") for v in data["variants"])
            pool = json.loads((pool_export / "manifest.json").read_text())
            assert not {"TileShade", "Worn"} & set(pool["materials"])
            assert all(m["color"] == POOL_TILE_RGB for m in pool["materials"].values()
                       if m.get("variant") in ("PR Tile", "PR Tile Aqua"))
            old = json.loads((EXPORT / "manifest.json").read_text())
            assert set(manifest["components"]) == set(pool["components"]) | {
                name for name in old["components"] if name.startswith("SlideCol_")}
            assert all(manifest["chunks"][i] == chunk for i, chunk in enumerate(pool["chunks"]))
            assert {chunk["wireSha256"] for chunk in manifest["chunks"][len(pool["chunks"]):]} == {
                chunk["wireSha256"] for chunk in old["chunks"]
                if chunk["component"].startswith("SlideCol_")}
            assert manifest["materials"]["Void"].get("variant") is None
            assert manifest["materials"]["Void"].get("pbr") is None
        two_hashes = iter(data["unique_wires"])
        try:
            importer.check_mesh_receipts({next(two_hashes): 7, next(two_hashes): 7})
        except ValueError:
            pass
        else:
            raise AssertionError("one mesh asset ID was accepted for two different wire hashes")
        two_textures = iter(data["texture_sources"])
        try:
            importer.check_mesh_receipts({next(two_textures): "rbxassetid://7",
                                          next(two_textures): "rbxassetid://7"}, "texture")
        except ValueError:
            pass
        else:
            raise AssertionError("one texture asset ID was accepted for two different image hashes")
        assert importer.djb2(b"abc") == 193485963, "audit digest regression"
        mesh_ledger = base / "fake_mesh_receipts.json"
        texture_ledger = base / "fake_texture_receipts.json"
        mesh_ledger.write_text(json.dumps({
            digest: {"wireSha256": digest, "assetId": 900000000 + index}
            for index, digest in enumerate(data["unique_wires"], 1)
        }), encoding="utf-8")
        texture_ledger.write_text(json.dumps({
            digest: {"sha256": digest, "assetId": f"rbxassetid://{800000000 + index}"}
            for index, digest in enumerate(data["texture_sources"], 1)
        }), encoding="utf-8")
        importer.MESH_RECEIPTS = mesh_ledger
        importer.TEXTURE_RECEIPTS = texture_ledger
        importer.stage_plan(data, importer.load_receipts(mesh_ledger),
                            importer.load_receipts(texture_ledger), "Level2BlenderKit", staging, verbose=False)
        planned = json.loads((staging / "plan.json").read_text(encoding="utf-8"))
        assert planned["installable"] and not planned["pendingMeshes"] and not planned["pendingTextures"]
        phases = sorted(staging.glob("[0-9][0-9][0-9]-*.luau"))
        assert len(phases) >= 3, f"missing staged installer phases: {list(staging.iterdir())}"
        assert phases[0].name.endswith("init.luau") and phases[-1].name.endswith("finalize.luau"), "phase order"
        fixture = "CornerCove_R8_H34" if profile == "poolrooms" else "DoorArch30"
        good = importer.component_record(fixture, manifest["components"][fixture],
                                         manifest["chunks"], importer.load_receipts(mesh_ledger),
                                         manifest["materials"], importer.load_receipts(texture_ledger),
                                         data["atlas_maps"])
        broken = json.loads(json.dumps(good))
        broken["name"] = fixture + "_Broken"
        broken["chunks"][0]["assetId"] = ""
        failed_phase = importer.component_phase(1, [good, broken], planned["kitName"],
                                                planned["manifestSha256"])
        rollback_source = (FAKE_ENGINE + "\n" + phase_function(phases[0], "initPhase") +
                           "local failed = pcall(function()\n" + failed_phase + "\nend)\n" +
                           "local stage = assert(SS:FindFirstChild('__Level2BlenderKit_Installing_" +
                           planned["manifestSha256"][:12] + "'))\n" +
                           "assert(not failed and #stage.Components:GetChildren() == 0 and " +
                           "stage:GetAttribute('NextPhase') == 1, 'partial component phase survived')\n" +
                           "print('ROLLBACK_OK')\n")
        rollback = run_luau(luau, rollback_source, staging, "fake_rollback.luau")
        assert rollback.returncode == 0 and "ROLLBACK_OK" in rollback.stdout, \
            f"interrupted phase left partial install: {rollback.stderr}"
        compiler = luau.with_name("luau-compile.exe")
        for phase in phases:
            subprocess.run([str(compiler), "--null", "-O0", str(phase)], check=True, capture_output=True)
        audit_payload = importer.audit_code(
            planned["kitName"], data, importer.load_receipts(mesh_ledger),
            importer.load_receipts(texture_ledger), planned["slideDataSlices"],
        )
        audit_path = staging / "audit.luau"
        audit_path.write_text(audit_payload, encoding="utf-8")
        subprocess.run([str(compiler), "--null", "-O0", str(audit_path)], check=True, capture_output=True)

        source = FAKE_ENGINE + "\n" + "\n".join(phase_function(p, f"phase{i}") for i, p in enumerate(phases))
        source += (
            "\nlocal beforeAudit = mutationCount\n"
            "local function auditPhase()\n" + audit_payload + "\nend\n"
            "local auditResult = auditPhase()\n"
            "assert(type(auditResult) == 'string' and string.find(auditResult, 'AUDIT OK', 1, true) == 1, 'audit result')\n"
            "assert(mutationCount == beforeAudit, 'audit mutated the tree')\n"
        )
        source += "\n" + overwrite_check(phases[0])
        pool_templates = ([name for name, info in pool["components"].items() if info["attrs"].get("Template")]
                          if profile == "poolrooms" else [])
        assert not pool_fixture or POOL_TEMPLATE_FIXTURE in pool_templates
        assert not set(pool_templates) & set(expected_inventory_names(importer, data))
        source += "\n" + make_checks(manifest, data, profile, pool_templates)
        if profile == "poolrooms":
            source += "\n" + AUDIT_NEGATIVES
        result = run_luau(luau, source, staging, "fake_install.luau")
        failure_lines = re.findall(r"fake_install\.luau:(\d+):", result.stderr)
        source_lines = source.splitlines()
        context = ""
        if failure_lines:
            n = min(map(int, failure_lines))
            context = "\n".join(f"{i}: {source_lines[i-1]}" for i in range(max(1, n-4), min(len(source_lines), n+4)+1))
        assert result.returncode == 0 and "KIT_IMPORT_FAKE_OK" in result.stdout, (
            f"installer failed under fake Luau:\n{result.stderr}\n{context}\n{result.stdout[-4000:]}"
        )
        match = re.search(r"SLIDES_JSON_BEGIN\s*\n(.*?)\nSLIDES_JSON_END", result.stdout, re.S)
        assert match, "SlidesJSON readback absent"
        assert profile != "poolrooms" or "AUDIT_NEGATIVES_OK 4" in result.stdout, "planted audit negatives did not run"
        assert json.loads(match.group(1)) == slides, "SlidesJSON readback differs from export"

        # Flip one actual marker constructor. The same oracle must reject the
        # resulting tree, proving it observes the installed classes.
        mutated, replacements = re.subn(
            r"Instance\.new\(([\"'])CFrameValue\1\)",
            'Instance.new("StringValue")', source, count=1,
        )
        assert replacements == 1, "no CFrameValue constructor found for mutation check"
        bad = run_luau(luau, mutated, staging, "fake_install_mutated.luau")
        assert bad.returncode != 0 or "KIT_IMPORT_FAKE_OK" not in bad.stdout, "mutation escaped the tree oracle"
    label = profile + (" (G1 fixture + synthetic Template component)" if pool_fixture else "")
    print(f"PASS {label}: plan, {len(phases)} compiled installer phases, read-only fake Luau audit, tree/readback, and marker mutation")


def expected_inventory_names(importer, data):
    return set(importer.expected_inventory(data, {}, {}))


def main():
    luau = Path(os.environ.get("LUAU_BIN", r"C:/Users/mikke/AppData/Local/Packages/OpenAI.Codex_2p2nqsd0c76g0/LocalCache/Local/CodexTools/luau/0.737/luau.exe"))
    assert luau.is_file(), f"Luau interpreter missing: {luau}"
    assert luau.with_name("luau-compile.exe").is_file(), "luau-compile.exe missing"
    run_profile("c", luau)
    run_profile("poolrooms", luau, pool_fixture=True)
    # The canonical export last: it fails (stale palette) until the kit is rebuilt with the G1 prkit.
    run_profile("poolrooms", luau)


if __name__ == "__main__":
    main()
