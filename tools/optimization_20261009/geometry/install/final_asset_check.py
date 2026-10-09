"""Read-only final native geometry check; no source staging or Instance writes.

Every target comes from the exact hashed postapply ledger. Union fingerprints
are reconstructed from the hashed before manifest with only Automatic LOD set.
The removed installer is never recreated or required.
"""
from __future__ import annotations

import argparse
import base64
import collections
import copy
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import sys

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[3]
sys.path.insert(0, str(ROOT / "tools"))
sys.path.insert(0, str(ROOT / "_local" / "optimization-20261009" / "vendor"))
from sync_from_studio import StudioMcpClient, find_mcp_batch
from run_geometry import compressed_export_action, decode_manifest
import zstandard

STUDIO = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
RECEIPT = HERE / "final-asset-check.json"


def stamp():
    return datetime.now(timezone.utc).isoformat()


def normalized_id(value):
    match = re.fullmatch(r"[0-9]+_([0-9]+)", value)
    assert match, "Unsupported GetDebugId representation: " + str(value)
    return match.group(1)


def read_pages(section):
    rows, hashes, first = [], [], 1
    for entry in section["pages"]:
        file = ROOT / entry["path"]
        raw = file.read_bytes()
        digest = hashlib.sha256(raw).hexdigest()
        assert digest == entry["sha256"], "Manifest page hash changed: " + str(file)
        page = json.loads(raw)
        assert page["startIndex"] == first and page["total"] == section["totalRows"]
        assert len(page["rows"]) == entry["rows"] and entry["first"] == first
        rows.extend(page["rows"])
        first += len(page["rows"])
        hashes.append({"path": entry["path"], "sha256": digest})
    assert len(rows) == section["totalRows"]
    return rows, hashes


def expected_targets(install):
    before, before_hashes = read_pages(install["manifest"])
    after, after_hashes = read_pages(install["postapplyLedger"])
    lod = {}
    originals = {}
    proxy_fingerprints = collections.Counter()
    for row in before:
        if row["kind"] == "renderFidelity":
            item = row["before"]
            assert json.loads(item["fingerprint"]) == item["values"]
            key = normalized_id(item["id"])
            assert key not in lod
            lod[key] = item
        elif row["kind"] == "exactColliderMerge":
            proxy_fingerprints[row["proxyExpectedFingerprint"]] += 1
            for item in row["before"]:
                key = normalized_id(item["id"])
                assert key not in originals
                originals[key] = item
        else:
            raise AssertionError("Unexpected installed geometry kind")
    result, seen = [], set()
    kinds = collections.Counter()
    for row in after:
        item = {key: row[key] for key in ("id", "path", "parentId", "className", "kind")}
        key = normalized_id(item["id"])
        assert key not in seen, "Normalized target identity collision"
        seen.add(key)
        if row["kind"] == "renderFidelity":
            baseline = lod.pop(key)
            assert item["path"] == baseline["path"] and normalized_id(item["parentId"]) == normalized_id(baseline["parentId"])
            assert row["renderFidelity"] == "Enum.RenderFidelity.Automatic"
            assert row["collisionFidelity"] == "Enum.CollisionFidelity.Hull"
            values = copy.deepcopy(baseline["values"])
            matches = 0
            for pair in values[4]:
                if pair[0] == "RenderFidelity":
                    assert pair[1] == ["EnumItem", "Enum.RenderFidelity.Precise"]
                    pair[1] = ["EnumItem", "Enum.RenderFidelity.Automatic"]
                    matches += 1
            assert matches == 1
            item["values"] = values
            old = '["RenderFidelity",["EnumItem","Enum.RenderFidelity.Precise"]]'
            new = '["RenderFidelity",["EnumItem","Enum.RenderFidelity.Automatic"]]'
            assert baseline["fingerprint"].count(old) == 1
            # Preserve exact native floating-point formatting. A JSON roundtrip
            # through Python can spell an identical binary float differently.
            item["fingerprint"] = baseline["fingerprint"].replace(old, new)
            assert json.loads(item["fingerprint"]) == values
        else:
            assert json.loads(row["fingerprint"]) == row["values"]
            item["values"] = row["values"]
            item["fingerprint"] = row["fingerprint"]
            if row["kind"] == "archivedMergedOriginal":
                baseline = originals.pop(key)
                assert row["fingerprint"] == baseline["fingerprint"]
            elif row["kind"] == "exactMergeProxy":
                assert proxy_fingerprints[row["fingerprint"]] > 0
                proxy_fingerprints[row["fingerprint"]] -= 1
            else:
                raise AssertionError("Unexpected postapply target kind")
        result.append(item)
        kinds[item["kind"]] += 1
    assert not lod and not originals and not +proxy_fingerprints
    assert len(result) == 6996
    assert kinds == {"renderFidelity": 6605, "archivedMergedOriginal": 267, "exactMergeProxy": 124}
    return result, {"beforePages": before_hashes, "postapplyPages": after_hashes, "targetKinds": dict(kinds)}


NATIVE = r'''
local H=game:GetService("HttpService")
local E=game:GetService("EncodingService")
local RS=game:GetService("RunService")
local function editOnly()
 assert(not RS:IsRunning(),"Authoritative Edit required")
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
end
editOnly()
local function normalize(id)
 local suffix=string.match(id,"^%d+_(%d+)$")
 assert(suffix,"Unsupported native GetDebugId representation")
 return suffix
end
local function hash(value)
 local binary=E:ComputeStringHash(value,Enum.HashAlgorithm.Sha256)
 local hex={}
 for i=1,#binary do hex[i]=string.format("%02x",string.byte(binary,i)) end
 return table.concat(hex)
end
local compressed=E:Base64Decode(buffer.fromstring(INPUT_BASE64))
local raw=buffer.tostring(E:DecompressBuffer(compressed,Enum.CompressionAlgorithm.Zstd))
assert(#raw==INPUT_BYTES and hash(raw)==INPUT_SHA256,"Inbound verification payload changed")
local input=H:JSONDecode(raw)
local function resolve(path)
 local node=game
 for name in string.gmatch(path,"[^.]+") do
  local matches={}
  for _,child in ipairs(node:GetChildren()) do if child.Name==name then table.insert(matches,child) end end
  assert(#matches==1,"Missing/ambiguous root path: "..path)
  node=matches[1]
 end
 return node
end
local roots, counts={},{}
for key,expected in pairs(input.roots) do
 local inst=resolve(expected.path)
 assert(normalize(inst:GetDebugId())==normalize(expected.id) and inst.ClassName==expected.className
  and normalize(inst.Parent:GetDebugId())==normalize(expected.parentId),"Recorded geometry root identity changed: "..key)
 roots[key]=inst
 counts[key]=#inst:GetDescendants()
end
assert(counts.collision==23332 and #roots.archive:GetChildren()==267,"Installed collision/archive counts changed")
local requested={}
for _,row in ipairs(input.rows) do
 local key=normalize(row.id)
 assert(not requested[key],"Duplicate requested normalized target identity")
 requested[key]=row
end
local matches={}
for _,root in pairs(roots) do
 for i,inst in ipairs(root:GetDescendants()) do
  local key=normalize(inst:GetDebugId())
  if requested[key] then
   assert(not matches[key],"Duplicate native normalized target identity")
   matches[key]=inst
  end
  if i%1000==0 then task.wait() end
 end
end
editOnly()
local function encodeValue(value)
 local kind=typeof(value)
 if kind=="Color3" then return {kind,value.R,value.G,value.B} end
 if kind=="Vector3" then return {kind,value.X,value.Y,value.Z} end
 if kind=="Vector2" then return {kind,value.X,value.Y} end
 if kind=="CFrame" then return {kind,value:GetComponents()} end
 if kind=="EnumItem" then return {kind,tostring(value)} end
 if kind=="BrickColor" then return {kind,value.Number} end
 if kind=="NumberRange" then return {kind,value.Min,value.Max} end
 assert(kind=="boolean" or kind=="number" or kind=="string","Unsupported native captured value: "..kind)
 return {kind,value}
end
local function nativeValues(inst,schema)
 local props,attrs,keys={},{},{}
 for _,pair in ipairs(schema[5]) do table.insert(props,{pair[1],encodeValue(inst[pair[1]])}) end
 local currentAttributes=inst:GetAttributes()
 for key in pairs(currentAttributes) do table.insert(keys,key) end
 table.sort(keys)
 for _,key in ipairs(keys) do table.insert(attrs,{key,encodeValue(currentAttributes[key])}) end
 local tags=inst:GetTags();table.sort(tags)
 local p=inst.CustomPhysicalProperties
 return {inst.ClassName,inst.Name,{inst.CFrame:GetComponents()},{inst.Size.X,inst.Size.Y,inst.Size.Z},props,
  p and {p.Density,p.Friction,p.Elasticity,p.FrictionWeight,p.ElasticityWeight} or false,attrs,tags,#inst:GetChildren()}
end
local output={first=input.first,total=input.total,checked=0,verified={},mismatches={},roots={},rootCounts=counts,
 nativeFingerprintSchemaExact=true,readOnly=true,placeId=game.PlaceId,universeId=game.GameId}
for index,row in ipairs(input.rows) do
 local inst=matches[normalize(row.id)]
 if not inst then table.insert(output.mismatches,{id=row.id,reason="missing"})
 else
  local identity=inst:GetFullName()==row.path and inst.ClassName==row.className and inst.Parent~=nil
   and normalize(inst.Parent:GetDebugId())==normalize(row.parentId)
  local ok,current=pcall(nativeValues,inst,row.values)
  if not ok then table.insert(output.mismatches,{id=row.id,reason="captured property read failed",detail=tostring(current)})
  else
   local fingerprint=H:JSONEncode(current)
   local expected=row.fingerprint
   assert(type(expected)=="string","Expected exact native fingerprint missing")
   local exact=fingerprint==expected
   if identity and exact then
    table.insert(output.verified,{id=row.id,actualId=inst:GetDebugId(),sha256=hash(fingerprint)})
   else
    local differences={}
    for slot=1,#row.values do
     if H:JSONEncode(current[slot])~=H:JSONEncode(row.values[slot]) then table.insert(differences,slot) end
    end
    table.insert(output.mismatches,{id=row.id,identityExact=identity,fingerprintExact=exact,currentPath=inst:GetFullName(),
     currentParentId=inst.Parent and inst.Parent:GetDebugId() or false,currentClass=inst.ClassName,differentValueSlots=differences,
     currentFingerprintSha256=hash(fingerprint),expectedFingerprintSha256=hash(expected)})
   end
  end
 end
 output.checked+=1
 if index%100==0 then task.wait();editOnly() end
end
for key,inst in pairs(roots) do
 local expected=input.roots[key]
 assert(inst:GetFullName()==expected.path and normalize(inst:GetDebugId())==normalize(expected.id)
  and inst.ClassName==expected.className and normalize(inst.Parent:GetDebugId())==normalize(expected.parentId),"Root identity changed during batch")
 assert(#inst:GetDescendants()==counts[key],"Root descendant count changed during batch")
 output.roots[key]={id=inst:GetDebugId(),path=inst:GetFullName(),parentId=inst.Parent:GetDebugId(),className=inst.ClassName}
end
editOnly()
output.exact=#output.mismatches==0 and #output.verified==#input.rows
return output
'''


def code_for(rows, roots, first, total):
    assert zstandard.__version__ == "0.25.0"
    raw = json.dumps({"rows": rows, "roots": roots, "first": first, "total": total}, ensure_ascii=True, separators=(",", ":")).encode()
    encoded = base64.b64encode(zstandard.ZstdCompressor(level=3).compress(raw)).decode("ascii")
    source = NATIVE.replace("INPUT_BASE64", json.dumps(encoded)).replace("INPUT_BYTES", str(len(raw))).replace("INPUT_SHA256", json.dumps(hashlib.sha256(raw).hexdigest()))
    return 'local H=game:GetService("HttpService")\nlocal result=(function()\n' + compressed_export_action(source) + '\nend)()\nreturn H:JSONEncode(result)'


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--page-size", type=int, default=200)
    parser.add_argument("--local-only", action="store_true", help="Review hashed manifests without connecting to Studio")
    parser.add_argument("--receipt-prefix", choices=("final", "prepublish"), default="final",
                        help="Separate prepublication evidence preserves all historical final receipts/pages")
    args = parser.parse_args()
    receipt_path = HERE / (args.receipt_prefix + "-asset-check.json")
    install_raw = (HERE / "runner-receipt.json").read_bytes()
    install = json.loads(install_raw)
    assert install["phase"] == "cleanupComplete" and install["studioId"] == STUDIO
    rows, local_evidence = expected_targets(install)
    if args.local_only:
        print(json.dumps({"targets": len(rows), "kinds": local_evidence["targetKinds"], "nativeChecksRun": False}))
        return
    roots = {key: install["postapplyLedger"][key] for key in ("archive", "collision", "level6")}
    receipt = {"phase": "running", "startedUtc": stamp(), "studioId": STUDIO, "datamodel": "Edit", "readOnly": True,
               "nativeBackupCreated": False, "studioInstancesCreated": False, "sourceWritten": False,
               "runnerReceiptSha256": hashlib.sha256(install_raw).hexdigest(), "expectedTotal": len(rows),
               "identityNormalization": "Decimal GetDebugId prefix is context-specific; exact decimal suffix, unique in bounded native scopes, is compared along with path, parent suffix and class. Native full IDs are captured.",
               "limitations": ["Hidden native union CSG/mesh/texture payload was not exposed by the captured properties and is not independently compared.",
                               "A sequential read-only Edit check is a time-window check, not an atomic publication lock.",
                               "This property/identity check alone does not establish gameplay, multiplayer, streaming or performance results."],
               "localEvidence": local_evidence, "pages": [], "checked": 0, "exact": False}
    if receipt_path.exists():
        previous = json.loads(receipt_path.read_text(encoding="utf-8"))
        receipt["previousAttempts"] = previous.get("previousAttempts", []) + [
            {key: previous.get(key) for key in ("phase", "startedUtc", "failedUtc", "error", "checked", "exact")}]
    destination = HERE / (args.receipt_prefix + "-asset-native-pages")
    destination.mkdir(exist_ok=True)

    def save():
        receipt_path.write_text(json.dumps(receipt, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")

    save()
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        available = json.loads(client.call("list_roblox_studios"))["studios"]
        assert any((studio.get("studio_id") or studio.get("id")) == STUDIO for studio in available), "Recorded authoritative Studio not connected"
        page_size = min(250, max(1, args.page_size))
        for first in range(1, len(rows) + 1, page_size):
            page_rows = rows[first-1:first-1+page_size]
            code = code_for(page_rows, roots, first, len(rows))
            native_raw = client.call("execute_luau", {"studio_id": STUDIO, "datamodel_type": "Edit", "code": code})
            page, raw, transport = decode_manifest(json.loads(native_raw))
            assert page["first"] == first and page["total"] == len(rows) and page["checked"] == len(page_rows)
            path = destination / ("page-%06d.json" % first)
            path.write_bytes(raw)
            receipt["pages"].append({"path": str(path.relative_to(ROOT)), "first": first, "rows": len(page_rows),
                                     "exact": page["exact"], "mismatches": page["mismatches"], **transport})
            receipt["checked"] += page["checked"]
            receipt["latestRoots"] = page["roots"]
            receipt["latestRootCounts"] = page["rootCounts"]
            receipt["lastCheckedUtc"] = stamp()
            save()
            print(json.dumps({"checked": receipt["checked"], "total": len(rows), "exact": page["exact"]}), flush=True)
            assert page["exact"], "Fresh authoritative geometry differs; inspect saved mismatch page"
        assert (HERE / "runner-receipt.json").read_bytes() == install_raw, "Installation ledger changed during check"
        receipt.update(phase="complete", exact=True, finishedUtc=stamp(), nativeFingerprintChecked=receipt["checked"],
                       normalizedIdentityChecked=receipt["checked"], targetKinds=local_evidence["targetKinds"])
        save()
    except Exception as problem:
        receipt.update(phase="failed", exact=False, failedUtc=stamp(), error=str(problem))
        save()
        raise
    finally:
        client.close()


if __name__ == "__main__":
    main()
