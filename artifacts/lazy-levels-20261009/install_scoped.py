"""Explicit single-source install using the previously verified native CAS contract.

Existing scripts require a fresh Source/editor capture. --new creates only the
named empty ModuleScript after proving that its native/mirror/manifest paths
are absent. Neither mode moves models, publishes, stages Git or bulk syncs.
"""
from pathlib import Path
import argparse
from datetime import datetime, timezone
import hashlib
import importlib.util
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
HERE = Path(__file__).resolve().parent
spec = importlib.util.spec_from_file_location("verified_source_installer", ROOT / "artifacts/stutter-assets-20261009/apply_source.py")
shared = importlib.util.module_from_spec(spec)
spec.loader.exec_module(shared)


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def add_module_code(name, source, originals):
    assert name == "LevelWorldStorage", "Only the requested storage module may be created"
    pins = [{key: row[key] for key in ("path", "class", "sha256")} for row in originals]
    assert len(pins) >= 10 and len({row["path"] for row in pins}) == len(pins), "Incomplete original inventory"
    return f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Wrong place")
assert(not game:GetService("RunService"):IsRunning(),"Requires Edit")
local parent=game:GetService("ServerScriptService")
local name={shared.luau_string(name)} local source={shared.luau_string(source)}
local SES=game:GetService("ScriptEditorService")
local function digest(value) local b=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(value),Enum.HashAlgorithm.Sha256) local t={{}} for i=0,buffer.len(b)-1 do t[i+1]=string.format("%02x",buffer.readu8(b,i)) end return table.concat(t) end
local originals=game:GetService("HttpService"):JSONDecode({shared.luau_string(json.dumps(pins))})
local function resolve(path)
 local current=game for name in path:gmatch("[^.]+") do
  local found for _,child in current:GetChildren() do if child.Name==name then assert(not found,"Original name collision") found=child end end
  current=assert(found,"Original missing: "..path)
 end return current
end
for _,row in originals do row.instance=resolve(row.path) end
local function originalGuard()
 for _,row in originals do local current=resolve(row.path)
  assert(current==row.instance and current.ClassName==row.class and digest(current.Source)==row.sha256 and SES:GetEditorSource(current)==current.Source,"Authoritative original changed: "..row.path)
 end
end
local function absent() for _,c in parent:GetChildren() do assert(c.Name~=name,"Target module already exists") end end
originalGuard() absent()
local s=Instance.new("ModuleScript")
assert(s.Source=="" and SES:GetEditorSource(s)=="","Fresh baseline is not empty")
absent() s.Name=name s.Parent=parent
local function guard()
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407 and not game:GetService("RunService"):IsRunning(),"Place/state changed")
 assert(s.Parent==parent and s.Name==name and s.ClassName=="ModuleScript","New identity changed")
 local count=0 for _,c in parent:GetChildren() do if c.Name==name then assert(c==s,"Target collision") count+=1 end end assert(count==1,"Target missing")
 assert(s.Source=="" and SES:GetEditorSource(s)=="","Empty source baseline changed")
 assert(s.Archivable and s.LinkedSource=="" and next(s:GetAttributes())==nil,"New metadata changed")
end
local ok,problem=xpcall(function()
 SES:UpdateSourceAsync(s,function(current) originalGuard() guard() assert(current=="","Callback changed") return source end)
end,debug.traceback)
originalGuard()
assert(ok,problem)
assert(s.Parent==parent and s.Name==name and s.Source==source and SES:GetEditorSource(s)==source,"Creation verification failed")
return game:GetService("HttpService"):JSONEncode({{path=s:GetFullName(),class=s.ClassName,bytes=#s.Source,sha256=digest(s.Source),editorSha256=digest(SES:GetEditorSource(s)),sourceEditorMatches=true,properties={{Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}},attributes=s:GetAttributes(),placeId=game.PlaceId,universeId=game.GameId}})
'''


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("baseline", type=Path)
    parser.add_argument("candidate", type=Path)
    parser.add_argument("mirror")
    parser.add_argument("label")
    parser.add_argument("--new", action="store_true")
    args = parser.parse_args()
    assert re.fullmatch(r"[A-Za-z0-9_.-]{1,80}", args.label)
    rel = args.mirror.replace("\\", "/")
    mirror = ROOT / rel
    assert not Path(rel).is_absolute() and mirror.resolve().is_relative_to(ROOT) and not mirror.is_symlink()
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_before = manifest_path.read_bytes()
    manifest = json.loads(manifest_before)
    candidate_raw = args.candidate.read_bytes()
    after = shared.normalize(candidate_raw.decode("utf-8"))
    baseline_raw = args.baseline.read_bytes()
    if args.new:
        assert rel == "ServerScriptService/LevelWorldStorage.ModuleScript.lua"
        assert not mirror.exists() and not any(row.get("file") == rel or row.get("studioPath") == "ServerScriptService.LevelWorldStorage" for row in manifest["items"])
        native = None
        before_raw = b""
        code = add_module_code("LevelWorldStorage", after, json.loads(baseline_raw))
    else:
        assert mirror.is_file()
        entry = shared.unique(manifest["items"], lambda row: row.get("file") == rel, "target manifest row")
        native = shared.unique(json.loads(baseline_raw), lambda row: row["path"] == entry["studioPath"], "fresh native baseline")
        assert native["class"] == entry["className"]
        before_raw = Path(native["sourceFile"]).read_bytes()
        assert len(before_raw) == native["bytes"] and sha(before_raw) == native["sha256"]
        assert before_raw.decode("utf-8") != after
        code = shared.install_code(native, before_raw.decode("utf-8"), after)
    mirror_before = mirror.read_bytes() if mirror.exists() else None
    checkpoint = ROOT / ".git/lazy-levels-20261009" / ("install-" + args.label)
    checkpoint.mkdir(parents=True, exist_ok=False)
    for name, raw in {"manifest-before.json": manifest_before, "baseline.json": baseline_raw,
                      "source-before.luau": before_raw, "candidate.luau": after.encode(), "install.luau": code.encode()}.items():
        (checkpoint / name).write_bytes(raw)
    if mirror_before is not None:
        (checkpoint / "mirror-before.lua").write_bytes(mirror_before)
    receipt_path = HERE / (args.label + "-native-install.json")
    assert not receipt_path.exists()
    receipt = {"task":"lazy-levels-20261009", "mirror":rel, "newModule":args.new,
               "beforeSHA256":sha(before_raw), "afterSHA256":sha(after.encode()), "baselineRecord":native,
               "nativeVerified":False, "mirrorExported":False, "published":False}
    try:
        assert manifest_path.read_bytes() == manifest_before and args.candidate.read_bytes() == candidate_raw
        assert args.baseline.read_bytes() == baseline_raw
        assert (mirror.read_bytes() if mirror.exists() else None) == mirror_before
        client = shared.StudioMcpClient(shared.find_mcp_batch())
        try:
            client.initialize()
            studio = shared.select_studio(client, shared.RELEASE_STUDIO_NAME, 20)
            result = json.loads(client.call("execute_luau", {"studio_id":studio["id"], "datamodel_type":"Edit", "code":code}))
        finally:
            client.close()
        assert result["sha256"] == result["editorSha256"] == receipt["afterSHA256"] and result["bytes"] == len(after.encode())
        assert result["sourceEditorMatches"] and result["placeId"] == 131311258779917 and result["universeId"] == 10559217407
        expected_path = "ServerScriptService.LevelWorldStorage" if args.new else native["path"]
        expected_class = "ModuleScript" if args.new else native["class"]
        assert result["path"] == expected_path and result["class"] == expected_class, "Native identity differs"
        receipt["nativeResult"] = result
        receipt["nativeVerified"] = True
        if not args.new:
            assert result["propertiesUnchanged"] and result["attributesUnchanged"]
            receipt.update(shared.export_verified(ROOT, rel, manifest_before, mirror_before, after))
        else:
            assert manifest_path.read_bytes() == manifest_before and not mirror.exists(), "Local creation baseline changed"
            row = {"studioPath":result["path"], "segments":result["path"].split("."), "className":result["class"], "file":rel,
                   "bytes":result["bytes"], "sha256":result["sha256"], "status":"synced", "sourceEditorMatches":True,
                   "properties":result["properties"], "attributes":result["attributes"]}
            manifest["items"].append(row)
            with mirror.open("xb") as handle:
                handle.write(after.encode())
            assert manifest_path.read_bytes() == manifest_before, "Manifest changed during export; native creation preserved"
            manifest_path.write_text(json.dumps(manifest, ensure_ascii=False, indent=2)+"\n", encoding="utf-8", newline="\n")
            assert mirror.read_bytes() == after.encode()
        receipt["mirrorExported"] = True
    except Exception as error:
        receipt["error"] = str(error)
        raise
    finally:
        receipt["capturedAtUtc"] = datetime.now(timezone.utc).isoformat()
        receipt["limits"] = "One explicitly requested source install/export; no gameplay, model relocation or publication claim"
        raw = (json.dumps(receipt, ensure_ascii=False, indent=2)+"\n").encode()
        (checkpoint / "receipt.json").write_bytes(raw)
        with receipt_path.open("xb") as handle:
            handle.write(raw)
    print(json.dumps({"mirror":rel, "nativeVerified":receipt["nativeVerified"], "mirrorExported":receipt["mirrorExported"], "sourceSHA256":receipt["afterSHA256"]}))


if __name__ == "__main__":
    main()
