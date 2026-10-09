"""Read-only exact eight-source check of the pinned authoritative Studio Edit.

Requires a fresh task-runtime JSON receipt. No staging, probes, source updates,
backups, mirror/global writes, Git actions or publication are performed.
"""
from __future__ import annotations
import argparse
from datetime import datetime, timezone
import hashlib
import json
import math
from pathlib import Path
import sys

sys.dont_write_bytecode = True
HERE = Path(__file__).resolve().parent
TASK = HERE.parents[3]
ROOT = TASK.parents[1]
MANIFEST = HERE / "verified-export-eight/manifest.json"
AUTHORITATIVE_STUDIO = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
IDENTITY_FIELDS = ("path", "name", "instanceId", "parentId", "parentPath", "parentClass")
OWNED = {
    ("ReplicatedFirst", "Lobby Loading Screen"): "LocalScript",
    ("ServerScriptService", "GameManager"): "Script",
    ("ServerScriptService", "Level 4 Systems", "Level 4 Light Director"): "ModuleScript",
    ("ReplicatedStorage", "SceneEffectBudget"): "ModuleScript",
    ("StarterPlayer", "StarterPlayerScripts", "SceneEffectBudgetClient"): "LocalScript",
    ("StarterPlayer", "StarterPlayerScripts", "Level 2 Sound Controller"): "LocalScript",
    ("StarterPlayer", "StarterPlayerScripts", "Level 6 Playground Client"): "LocalScript",
    ("StarterPlayer", "StarterPlayerScripts", "SpectateController"): "LocalScript",
}
sys.path.insert(0, str(TASK))
sys.path.insert(0, str(TASK / "verified-export"))
from native_probe_runner import StudioMcpClient, find_mcp_batch, literal
from export_verified_sources import GUARD


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def primitive_map(value):
    if value == []:
        value = {}
    assert isinstance(value, dict), "Expected primitive property/attribute map"
    assert all(isinstance(key, str) and isinstance(item, (str, bool, int, float))
        and (not isinstance(item, (int, float)) or math.isfinite(item)) for key, item in value.items())
    return value


def load_expected():
    raw_manifest = MANIFEST.read_bytes()
    manifest = json.loads(raw_manifest)
    assert manifest["complete"] is True and manifest["readOnly"] is True and manifest["datamodel"] == "Edit"
    assert manifest["placeId"] == 131311258779917 and manifest["universeId"] == 10559217407
    rows = manifest["scripts"]
    assert len(rows) == len({tuple(row["segments"]) for row in rows}) == 8
    assert {tuple(row["segments"]): row["class"] for row in rows} == OWNED
    historical_path = (ROOT / manifest["historicalSevenManifest"]).resolve()
    assert historical_path == (TASK / "verified-export/manifest.json").resolve()
    historical_raw = historical_path.read_bytes()
    assert sha(historical_raw) == manifest["historicalSevenManifestSha256"]
    sid = json.loads(historical_raw)["studioId"]
    assert sid == json.loads((HERE / "baseline-capture.json").read_bytes())["studioId"] == AUTHORITATIVE_STUDIO
    expected = []
    for row in rows:
        raw_path = (ROOT / row["rawFile"]).resolve()
        assert raw_path.is_relative_to(TASK), "Raw source outside task scope"
        raw = raw_path.read_bytes()
        assert sha(raw) == row["rawSourceSha256"] == row["reviewedCandidateSha256"] == row["sourceSha256"]
        assert len(raw) == row["rawBytes"] and row["rawUtf8Verified"] is True
        assert row["editorParity"] is True and row["reviewedCandidateMatches"] is True
        identity = {key: row[key] for key in IDENTITY_FIELDS}
        assert all(isinstance(value, str) and value for value in identity.values())
        assert identity["path"] == ".".join(row["segments"]) and identity["name"] == row["segments"][-1]
        assert identity["parentPath"] == ".".join(row["segments"][:-1])
        properties = primitive_map(row["properties"])
        assert set(properties) == ({"Archivable", "LinkedSource"} if row["class"] == "ModuleScript"
            else {"Archivable", "LinkedSource", "Disabled", "RunContext"})
        expected.append({"segments": row["segments"], "class": row["class"], "identity": identity,
            "source": raw.decode("utf-8"), "sha256": sha(raw), "rawBytes": len(raw),
            "properties": properties, "attributes": primitive_map(row["attributes"]),
            "rawFile": row["rawFile"], "expectedRepositoryPath": row["expectedRepositoryPath"]})
    return expected, sha(raw_manifest), sid


def make_code(expected):
    return GUARD + '''
local expected=H:JSONDecode(%s)
local function sameMap(actual,wanted,label)
 for key,value in pairs(wanted) do assert(actual[key]==value,label.." differs: "..key) end
 for key in pairs(actual) do assert(wanted[key]~=nil,label.." unexpected: "..key) end
end
local pins={}
for _,row in ipairs(expected) do
 local n,s=check(row)
 local properties={}
 for _,key in ipairs({"Archivable","LinkedSource","Disabled","RunContext"}) do
  local ok,value=pcall(function() return n[key] end)
  if ok then properties[key]=if typeof(value)=="EnumItem" then tostring(value) else value end
 end
 local attributes={}
 for key,value in pairs(n:GetAttributes()) do
  if typeof(value)=="string" or typeof(value)=="boolean" or typeof(value)=="number" then attributes[key]=value end
 end
 sameMap(properties,row.properties,"Source properties: "..n:GetFullName())
 sameMap(attributes,row.attributes,"Primitive attributes: "..n:GetFullName())
 table.insert(pins,{path=n:GetFullName(),segments=row.segments,class=n.ClassName,name=n.Name,
  instanceId=n:GetDebugId(16),parentId=n.Parent:GetDebugId(16),parentPath=n.Parent:GetFullName(),parentClass=n.Parent.ClassName,
  rawBytes=#s,sourceSha256=row.sha256,editorParity=true,reviewedCandidateMatches=true,
  properties=properties,attributes=attributes})
end
return H:JSONEncode({verifiedUtc=os.date("!%%Y-%%m-%%dT%%H:%%M:%%SZ"),readOnly=true,complete=true,pins=pins})
''' % literal(expected)


def validate_result(result, expected):
    assert result["complete"] is True and result["readOnly"] is True
    pins = result["pins"]
    assert len(pins) == len({pin["path"] for pin in pins}) == len(expected) == 8
    for row, pin in zip(expected, pins):
        assert pin["segments"] == row["segments"] and pin["class"] == row["class"]
        assert pin["rawBytes"] == row["rawBytes"] and pin["sourceSha256"] == row["sha256"]
        assert pin["editorParity"] is True and pin["reviewedCandidateMatches"] is True
        assert all(pin[key] == row["identity"][key] for key in IDENTITY_FIELDS)
        assert primitive_map(pin["properties"]) == row["properties"]
        assert primitive_map(pin["attributes"]) == row["attributes"]
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--receipt", required=True, type=Path, help="Fresh JSON path under tools/optimization_20261009/runtime")
    args = parser.parse_args()
    output = (ROOT / args.receipt).resolve()
    assert output.is_relative_to((TASK / "runtime").resolve()) and output.suffix == ".json"
    assert not output.exists(), "Preserve prior receipts; choose a fresh receipt name"
    expected, manifest_hash, sid = load_expected()
    receipt = {"startedUtc": datetime.now(timezone.utc).isoformat(), "complete": False,
        "studioId": sid, "datamodel": "Edit", "placeId": 131311258779917, "universeId": 10559217407,
        "readOnly": True, "studioMutation": False, "nativeBackup": False, "probeCreated": False,
        "runtimeMirrorsWritten": False, "globalManifestWritten": False, "gitStaged": False,
        "expectedManifest": MANIFEST.relative_to(ROOT).as_posix(), "expectedManifestSha256": manifest_hash,
        "reviewedSources": 8, "rawUtf8SourceBytes": sum(row["rawBytes"] for row in expected)}
    output.parent.mkdir(parents=True, exist_ok=True)
    def save():
        output.write_bytes((json.dumps(receipt, indent=2, ensure_ascii=False) + "\n").encode("utf-8"))
    save()
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        code = make_code(expected)
        def check_all():
            raw = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
            assert len(raw.encode("utf-8")) <= 12000, "Native read response exceeds bounded output"
            return validate_result(json.loads(raw), expected)
        receipt["nativeBegin"] = check_all()
        assert load_expected() == (expected, manifest_hash, sid), "Local reviewed capture changed during native check"
        receipt["nativeEnd"] = check_all()
        assert load_expected() == (expected, manifest_hash, sid), "Local reviewed capture changed after native check"
        receipt["allEightExactSourceEditorIdentityPropertiesAttributes"] = True
        receipt["complete"] = True
    except Exception as error:
        receipt["error"] = type(error).__name__ + ": " + str(error)
        raise
    finally:
        receipt["finishedUtc"] = datetime.now(timezone.utc).isoformat()
        save()
        client.close()
    print("Exact eight native Source/editor/identity/properties/primitive attributes verified twice in authoritative Edit; receipt only written.")


if __name__ == "__main__":
    main()
