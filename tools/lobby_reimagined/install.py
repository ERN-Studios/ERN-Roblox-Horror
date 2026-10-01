#!/usr/bin/env python3
"""Generate a reviewed SHA-pinned additive Studio installer; never connect to Studio."""
import argparse
import json
from pathlib import Path
from serve import load_package, sha

TEMPLATE = r'''-- New isolated lobby preview only. Generated from a locally verified package.
local HS = game:GetService("HttpService")
local ENC = game:GetService("EncodingService")
local RunService = game:GetService("RunService")
local BASE = __BASE__
local PLAN_JSON = __PLAN__
local PLAN = HS:JSONDecode(PLAN_JSON)
assert(game.PlaceId == PLAN.placeId and game.GameId == PLAN.universeId and game.CreatorId == PLAN.groupId, "Wrong preview experience/owner")
assert(not RunService:IsRunning(), "Preview install requires Edit mode")
local SS = game:GetService("ServerStorage")
local SSS = game:GetService("ServerScriptService")
local RS = game:GetService("ReplicatedStorage")
local SPS = game:GetService("StarterPlayer"):FindFirstChild("StarterPlayerScripts")
assert(SPS, "StarterPlayerScripts is absent; preserve current Studio")
local SERVER, CLIENT = "LobbyReimaginedPreview", "LobbyReimaginedQueueController"
local wantsRS, wantsClient = false, false
for _, spec in ipairs(PLAN.sources) do
    if spec.path:sub(1,18) == "ReplicatedStorage." then wantsRS = true end
    if spec.class == "LocalScript" then wantsClient = true end
end
local function absent()
    assert(not SS:FindFirstChild(PLAN.sourceName), "Preview raw source exists; refusing overwrite")
    assert(not SSS:FindFirstChild(SERVER), "Preview server namespace exists; refusing overwrite")
    if wantsRS then assert(not RS:FindFirstChild(SERVER), "Preview replicated namespace exists") end
    if wantsClient then assert(not SPS:FindFirstChild(CLIENT), "Preview queue controller exists") end
end
absent()
local function sha(raw)
    local digest = ENC:ComputeBufferHash(raw, Enum.HashAlgorithm.Sha256)
    local chars = table.create(buffer.len(digest))
    for i = 0, buffer.len(digest)-1 do chars[i+1] = string.format("%02x", buffer.readu8(digest,i)) end
    return table.concat(chars)
end
local staged = {}
local function folder(name)
    local item = Instance.new("Folder"); item.Name = name
    item:SetAttribute("LobbyReimaginedOwned", true)
    return item
end
local source, server, replicated = folder(PLAN.sourceName), folder(SERVER), if wantsRS then folder(SERVER) else nil
source:SetAttribute("Ready", false)
table.insert(staged, source); table.insert(staged, server)
if replicated then table.insert(staged, replicated) end
local function compressed(name, raw, parent, expected)
    assert(buffer.len(raw) == expected.bytes and sha(raw) == expected.sha256, "Source payload hash differs: "..name)
    local item = folder(name)
    item.Parent = parent -- Track new compressed children before any yielding/error-prone operation.
    local packed = ENC:CompressBuffer(raw, Enum.CompressionAlgorithm.Zstd, 3)
    local text = buffer.tostring(ENC:Base64Encode(packed))
    for offset = 1, #text, 60000 do
        local value = Instance.new("StringValue")
        value.Parent = item
        value.Name = string.format("%05d", math.floor((offset-1)/60000))
        value.Value = text:sub(offset,offset+59999)
    end
    item:SetAttribute("RawBytes", buffer.len(raw)); item:SetAttribute("CompressedBytes", buffer.len(packed))
    item:SetAttribute("RawSHA256", expected.sha256)
end
local previousHttp = HS.HttpEnabled
local client
local ok, why = pcall(function()
    HS.HttpEnabled = true
    assert(HS:GetAsync(BASE.."/source-module-manifest", true) == PLAN_JSON, "Server package/source plan differs from reviewed installer")
    local manifestText = HS:GetAsync(BASE.."/manifest", true)
    compressed("ManifestJSON", buffer.fromstring(manifestText), source, {bytes=PLAN.manifestBytes,sha256=PLAN.manifestSha256})
    local manifest = HS:JSONDecode(manifestText)
    assert(manifest.schema == "lobby-reimagined-blender-v1" and #manifest.chunks == #PLAN.chunks, "Wrong preview manifest")
    local meshes = folder("Meshes"); meshes.Parent = source
    for index, chunk in ipairs(PLAN.chunks) do
        assert(chunk.id == index-1, "Unordered chunk IDs")
        local raw = ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/chunk/"..chunk.id, true)))
        assert(buffer.readu32(raw,0) == 0x364D564C and buffer.readu32(raw,16) == chunk.triangles, "Wrong mesh geometry header")
        compressed(tostring(chunk.id), raw, meshes, {bytes=chunk.bytes,sha256=chunk.sha256})
        task.wait()
    end
    local pixels = ENC:Base64Decode(buffer.fromstring(HS:GetAsync(BASE.."/atlas-pixels", true)))
    compressed("AtlasPixels", pixels, source, PLAN.atlas)
    source:SetAttribute("ManifestSHA256", PLAN.manifestSha256)
    source:SetAttribute("AtlasSHA256", PLAN.atlas.sha256); source:SetAttribute("Ready", true)
    for _, spec in ipairs(PLAN.sources) do
        local text = HS:GetAsync(BASE.."/script/"..spec.key, true)
        assert(#text == spec.bytes and sha(buffer.fromstring(text)) == spec.sha256, "Candidate Source changed: "..spec.key)
        local item = Instance.new(spec.class)
        table.insert(staged,item) -- Track even when Studio rejects a Source/property assignment.
        item.Name = spec.path:match("([^%.]+)$"); item.Source = text
        item:SetAttribute("LobbyReimaginedOwned", true); item:SetAttribute("InstalledSourceSHA256", spec.sha256)
        if spec.class == "LocalScript" then client = item
        elseif spec.path:sub(1,18) == "ReplicatedStorage." then item.Parent = assert(replicated)
        else item.Parent = server end
    end
    assert(not RunService:IsRunning(), "Studio entered Play during install")
    absent() -- Compare fresh absence after every download, immediately before any parenting.
    source.Parent = SS
    server.Parent = SSS
    if replicated then replicated.Parent = RS end
    if client then client.Parent = SPS end
end)
HS.HttpEnabled = previousHttp
if not ok then
    for index = #staged,1,-1 do pcall(function() staged[index]:Destroy() end) end -- Only newly created objects.
    error(why)
end
return {Installed=true,Source=source:GetFullName(),ManifestSHA256=PLAN.manifestSha256,Chunks=#PLAN.chunks,Sources=#PLAN.sources}
'''


def long_string(value):
    for depth in range(1, 20):
        equals = "=" * depth
        if "]" + equals + "]" not in value:
            return "[" + equals + "[" + value + "]" + equals + "]"
    raise ValueError("Cannot represent Lua string")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("package", type=Path)
    parser.add_argument("--output", type=Path, required=True)
    parser.add_argument("--port", type=int, default=8892)
    parser.add_argument("--sources-manifest", type=Path)
    args = parser.parse_args()
    assert 1024 <= args.port <= 65535
    package = load_package(args.package, args.sources_manifest)
    plan = json.dumps(package["plan"], separators=(",", ":"))
    text = TEMPLATE.replace("__BASE__", long_string(f"http://127.0.0.1:{args.port}")).replace("__PLAN__", long_string(plan))
    payload = text.encode()
    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.output.exists() and args.output.read_bytes() != payload:
        raise SystemExit("Refusing to overwrite a different reviewed installer: " + str(args.output))
    args.output.write_bytes(payload)
    receipt = {"schema": "lobby-reimagined-generated-installer-v1", "output": str(args.output),
               "sha256": sha(payload), "bytes": len(payload), "manifestSha256": package["plan"]["manifestSha256"],
               "chunks": len(package["chunks"]), "sources": package["plan"]["sources"],
               "scope": "Generate local candidate only; no Studio connection, installation, upload or publish"}
    args.output.with_suffix(".receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
