"""Install one reviewed candidate using an explicit fresh Studio baseline.

Usage: apply_source.py BASELINE_SOURCES_JSON CANDIDATE_LUAU MIRROR_RELATIVE_PATH LABEL
Only the named Source, mirror and manifest entry are written. No pending flags,
instance creation, settings changes, publication or bulk synchronization.
"""
from __future__ import annotations

import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from push_repo_to_studio import luau_string
from studio_source_contract import canonical_bytes, normalize, sha256_of
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME


def digest(raw: bytes) -> str:
    return hashlib.sha256(raw).hexdigest()


def unique(rows, predicate, label):
    found = [row for row in rows if predicate(row)]
    assert len(found) == 1, f"Expected one {label}; found {len(found)}"
    return found[0]


def literal(value):
    if isinstance(value, str):
        return luau_string(value)
    if isinstance(value, bool):
        return str(value).lower()
    assert isinstance(value, (int, float)) and math.isfinite(value), "Unsupported baseline value"
    return repr(value)


def install_code(native, before: str, after: str) -> str:
    assert native["class"] in {"Script", "LocalScript", "ModuleScript"}, "Not a source container"
    segments = native["path"].split(".")
    assert len(segments) >= 2 and all(segments), "Invalid exact instance path"
    encoded_segments = "{" + ",".join(luau_string(s) for s in segments) + "}"
    checks = []
    properties = native["properties"]
    assert set(properties) <= {"Archivable", "LinkedSource", "Disabled", "RunContext"}, "Unsupported property guard"
    assert {"Archivable", "LinkedSource"} <= set(properties), "Incomplete property baseline"
    if native["class"] != "ModuleScript":
        assert {"Disabled", "RunContext"} <= set(properties), "Incomplete BaseScript baseline"
    for key, value in properties.items():
        lhs = f"s[{luau_string(key)}]"
        if key in {"RunContext", "LinkedSource"}:
            lhs = f"tostring({lhs})"
        checks.append(f"assert({lhs}=={literal(value)},{luau_string('Property changed: ' + key)})")
    attributes = native["attributes"]
    if attributes == []:
        attributes = {}
    assert isinstance(attributes, dict), "Attributes must be a dictionary or an empty Lua array"
    checks.append(f'local attrs=s:GetAttributes() local count=0 for _ in attrs do count+=1 end assert(count=={len(attributes)},"Attributes changed")')
    for key, value in attributes.items():
        checks.append(f"assert(attrs[{luau_string(key)}]=={literal(value)},{luau_string('Attribute changed: ' + key)})")
    return f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place/universe")
assert(not game:GetService("RunService"):IsRunning(),"Requires Edit state")
local segments={encoded_segments}
local function resolve()
 local cursor=game
 for _,name in segments do
  local found=nil
  for _,child in cursor:GetChildren() do
   if child.Name==name then assert(not found,"Ambiguous instance path") found=child end
  end
  cursor=assert(found,"Missing instance path")
 end
 return cursor
end
local s=resolve()
local SES=game:GetService("ScriptEditorService")
local before={luau_string(before)} local after={luau_string(after)}
local function identityGuard()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not game:GetService("RunService"):IsRunning(),"Place or Edit state changed")
 assert(resolve()==s and s:IsDescendantOf(game) and s:GetFullName()=={luau_string(native["path"])},"Instance identity/path changed")
 assert(s.ClassName=={luau_string(native["class"])},"Class changed")
 {" ".join(checks)}
end
local function baselineGuard()
 identityGuard()
 assert(s.Source==before,"Native Source changed")
 assert(SES:GetEditorSource(s)==before,"Editor source changed")
end
baselineGuard()
SES:UpdateSourceAsync(s,function(current)
 baselineGuard()
 assert(current==before,"Callback baseline changed")
 return after
end)
identityGuard()
assert(s.Source==after,"Native candidate mismatch after install")
assert(SES:GetEditorSource(s)==after,"Editor candidate mismatch after install")
local ENC=game:GetService("EncodingService")
local function sha(text)
 local hash=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local hex={{}} for i=0,buffer.len(hash)-1 do hex[i+1]=string.format("%02x",buffer.readu8(hash,i)) end
 return table.concat(hex)
end
return game:GetService("HttpService"):JSONEncode({{path=s:GetFullName(),class=s.ClassName,
 bytes=#s.Source,sha256=sha(s.Source),editorSha256=sha(SES:GetEditorSource(s)),sourceEditorMatches=true,
 placeId=game.PlaceId,universeId=game.GameId,placeVersion=game.PlaceVersion,propertiesUnchanged=true,attributesUnchanged=true}})
'''


def export_verified(root: Path, rel: str, manifest_before: bytes, mirror_before: bytes, source: str):
    manifest_path = root / "studio-sync-manifest.json"
    requested_mirror = root / rel
    mirror = requested_mirror.resolve()
    assert mirror.is_relative_to(root.resolve()) and not Path(rel).is_absolute(), "Mirror escapes repository"
    assert mirror.is_file() and not requested_mirror.is_symlink(), "Expected an existing regular mirror"
    manifest = json.loads(manifest_before)
    entry = unique(manifest["items"], lambda row: row.get("file") == rel, "manifest mirror entry")
    entry.update(bytes=len(canonical_bytes(source)), sha256=sha256_of(source), status="synced", sourceEditorMatches=True)
    entry.pop("studioSha256Before", None)
    entry.pop("studioTrailingNewline", None)
    updated = (json.dumps(manifest, ensure_ascii=False, indent=2) + "\n").encode()
    assert manifest_path.read_bytes() == manifest_before, "Manifest changed concurrently; reconcile fresh local state"
    assert mirror.read_bytes() == mirror_before, "Mirror changed concurrently; preserve fresh local work"
    mirror.write_bytes(source.encode())
    assert mirror.read_bytes() == source.encode(), "Mirror readback failed"
    assert manifest_path.read_bytes() == manifest_before, "Manifest changed during mirror export; recovery checkpoint retained"
    manifest_path.write_bytes(updated)
    assert manifest_path.read_bytes() == updated, "Manifest readback failed"
    return {"mirrorSha256": digest(mirror.read_bytes()), "manifestSha256": digest(updated)}


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("mirror")
    parser.add_argument("label")
    args = parser.parse_args()
    assert re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", args.label), "Unsafe checkpoint label"
    rel = args.mirror.replace("\\", "/")
    requested_mirror = ROOT / rel
    mirror = requested_mirror.resolve()
    assert mirror.is_relative_to(ROOT) and not Path(rel).is_absolute(), "Mirror escapes repository"
    assert mirror.is_file() and not requested_mirror.is_symlink(), "Expected an existing regular mirror"
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_before, mirror_before = manifest_path.read_bytes(), mirror.read_bytes()
    entry = unique(json.loads(manifest_before)["items"], lambda row: row.get("file") == rel, "manifest mirror entry")
    baseline_raw, candidate_raw = args.baseline.read_bytes(), args.candidate.read_bytes()
    native = unique(json.loads(baseline_raw), lambda row: row["path"] == entry["studioPath"], "explicit baseline record")
    assert native["class"] == entry["className"], "Manifest/baseline class differs"
    source_file = Path(native["sourceFile"])
    before_raw = source_file.read_bytes()
    assert len(before_raw) == native["bytes"] and digest(before_raw) == native["sha256"], "Baseline file/hash differs"
    before, after = before_raw.decode(), normalize(candidate_raw.decode())
    assert before != after, "No scoped source change"
    code = install_code(native, before, after)
    checkpoint = ROOT / ".git" / "stutter-assets-20261009" / ("install-" + args.label)
    checkpoint.mkdir(parents=True, exist_ok=False)
    for name, raw in {"manifest-before.json": manifest_before, "mirror-before.lua": mirror_before,
                      "baseline-sources.json": baseline_raw, "source-before.luau": before_raw,
                      "candidate.luau": after.encode(), "install.luau": code.encode()}.items():
        (checkpoint / name).write_bytes(raw)
    receipt = {"task": "stutter-assets-20261009", "label": args.label, "path": native["path"], "class": native["class"],
               "mirror": rel, "baselineFile": str(args.baseline.resolve()), "baselineSHA256": digest(baseline_raw),
               "baselineRecord": native, "beforeSHA256": digest(before_raw), "afterSHA256": digest(after.encode()),
               "candidateFile": str(args.candidate.resolve()), "candidateFileSHA256": digest(candidate_raw),
               "mirrorBeforeSHA256": digest(mirror_before), "manifestBeforeSHA256": digest(manifest_before),
               "checkpoint": str(checkpoint), "nativeVerified": False, "mirrorExported": False, "published": False}
    receipt_path = ROOT / "artifacts" / "stutter-assets-20261009" / (args.label + "-native-install.json")
    assert not receipt_path.exists(), "Do not overwrite an install receipt"
    try:
        assert args.baseline.read_bytes() == baseline_raw and source_file.read_bytes() == before_raw, "Baseline files changed"
        assert args.candidate.read_bytes() == candidate_raw, "Candidate changed before install"
        assert manifest_path.read_bytes() == manifest_before and mirror.read_bytes() == mirror_before, "Local files changed before install"
        client = StudioMcpClient(find_mcp_batch())
        try:
            client.initialize()
            studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
            result = json.loads(client.call("execute_luau", {"studio_id": studio["id"], "datamodel_type": "Edit", "code": code}))
        finally:
            client.close()
        receipt["nativeResult"] = result
        assert result["path"] == native["path"] and result["class"] == native["class"]
        assert result["bytes"] == len(after.encode()) and result["sha256"] == result["editorSha256"] == receipt["afterSHA256"]
        assert result["sourceEditorMatches"] and result["propertiesUnchanged"] and result["attributesUnchanged"]
        assert result["placeId"] == 131311258779917 and result["universeId"] == 10559217407
        receipt["nativeVerified"] = True
        assert args.candidate.read_bytes() == candidate_raw, "Candidate changed after install; export blocked"
        receipt.update(export_verified(ROOT, rel, manifest_before, mirror_before, after))
        receipt["mirrorExported"] = True
    except Exception as error:
        receipt["error"] = str(error)
        raise
    finally:
        receipt["capturedAtUtc"] = datetime.now(timezone.utc).isoformat()
        receipt["limits"] = "Exact single native Source/editor install and scoped mirror export only; no compilation, gameplay, asset loading, performance or publication claim."
        raw = (json.dumps(receipt, ensure_ascii=False, indent=2) + "\n").encode()
        (checkpoint / "receipt.json").write_bytes(raw)
        with receipt_path.open("xb") as handle:
            handle.write(raw)
    print(json.dumps(receipt, ensure_ascii=False))


if __name__ == "__main__":
    main()
