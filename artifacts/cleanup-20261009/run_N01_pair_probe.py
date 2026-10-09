"""Run one owned Client scenario probe; never clone or rewrite a live script.

Usage: python artifacts/cleanup-20261009/run_N01_pair_probe.py pair-before
       python artifacts/cleanup-20261009/run_N01_pair_probe.py pair-current

Historical inputs are pinned in N01-pair-proof/index.json. Both QA probes use
the existing current gameplay owner; this is not a runtime-before swap. Never
run against an owner's active Play without explicit authorization. See the
proof README before any later native use; this archive repair runs no gate.
"""
from pathlib import Path
from datetime import datetime, timezone
import argparse
import hashlib
import json
import re
import sys

ROOT = Path(__file__).resolve().parents[2]
CHECKPOINT = ROOT / ".git/mongotv-cleanup-20261009"
PROOF_DIR = Path(__file__).with_name("N01-pair-proof")
PROOF_SHA256 = {
    "UIRegression.N01.pair-before.lua": "3538ab55abc952bebefddf5c9572adcfd7426787a5c52d1b4df215df97335736",
    "UIRegression.N01.pair-current.lua": "9eb0749a60443df8aba71da89743d6845d49917388c6082fe033c83366b9e951",
    "UIRegression.N01.touch-probe-before.lua": "5b1a67dac9c14e977c660d45ffaaf966c6d86faf71dcac6b3a8f36ea757c4c46",
    "UIRegression.N01.touch-probe-current.lua": "40de1004e0b6ce62793cad6032881eccb21872f06006d5bc06b336743a46ff8d",
    "UIRegression.N01.touch-probe-reset.lua": "afbda7183420de6dabde39ef4953b4bb1fe17bbff855a17737c263eb04a5fe2a",
}
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string


def sha_lf(path):
    return hashlib.sha256(path.read_bytes().replace(b"\r\n", b"\n")).hexdigest()


def load_probe(suffix):
    filename = f"UIRegression.N01.{suffix}.lua"
    assert filename in PROOF_SHA256, "unknown historical probe"
    index = json.loads((PROOF_DIR / "index.json").read_text(encoding="utf8"))
    assert index["schemaVersion"] == 1, "unsupported proof index"
    rows = {row["file"]: row for row in index["files"]}
    assert len(index["files"]) == len(rows) and set(rows) == set(PROOF_SHA256), "proof index inventory drift"
    row = rows[filename]
    raw = (PROOF_DIR / filename).read_bytes()
    normalized = raw.replace(b"\r\n", b"\n")
    assert hashlib.sha256(raw).hexdigest() == row["rawSha256"] == PROOF_SHA256[filename], "historical probe raw hash drift"
    assert hashlib.sha256(normalized).hexdigest() == row["lfSha256"] == PROOF_SHA256[filename], "historical probe LF hash drift"
    assert len(raw) == row["rawBytes"] and len(normalized) == row["lfBytes"], "historical probe length drift"
    return raw.decode("utf8")


def unwrap(result):
    data = json.loads(result)
    if isinstance(data, dict) and "content" in data:
        for entry in data["content"]:
            if entry.get("type") == "text":
                try:
                    value = json.loads(entry["text"])
                except (ValueError, TypeError):
                    continue
                if isinstance(value, dict) and "phase" in value:
                    return value
    return data


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("phase", choices=["pair-before", "pair-current", "pair-reset"])
    parser.add_argument("--lane", choices=["scenarios", "touch"], default="scenarios")
    parser.add_argument("--receipt-label", help="Separate new receipt label for an explicitly authorized historical replay")
    args = parser.parse_args()
    if args.phase == "pair-reset" and args.lane != "touch":
        parser.error("pair-reset is only defined for --lane touch")
    label = args.phase.removeprefix("pair-")
    suffix = f"pair-{label}" if args.lane == "scenarios" else f"touch-probe-{label}"
    entrypoint = "CleanupScenarioPair" if args.lane == "scenarios" else "CleanupTouchLifecycleProbe"
    receipt_label = args.phase if args.lane == "scenarios" else f"touch-{label}"
    output_label = args.receipt_label or f"B06-{receipt_label}"
    assert re.fullmatch(r"[A-Za-z0-9-]+", output_label), "unsafe receipt label"
    receipt_output = Path(__file__).with_name(output_label + ".json")
    assert not receipt_output.exists(), "historical receipt already exists; select a new replay receipt label"
    source = load_probe(suffix)
    ui_hash = sha_lf(ROOT / "ReplicatedStorage/UIRegression.ModuleScript.lua")
    hud_hash = sha_lf(ROOT / "ReplicatedStorage/RoundHud.ModuleScript.lua")
    code = f'''
assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local SES=game:GetService("ScriptEditorService")
local HS=game:GetService("HttpService")
local ENC=game:GetService("EncodingService")
local RS=game:GetService("ReplicatedStorage")
local function unique(name)
 local found=nil
 for _,child in RS:GetChildren() do
  if child.Name==name then assert(not found,"ambiguous module path") found=child end
 end
 assert(found and found.ClassName=="ModuleScript","missing or changed module class")
 return found
end
local live,owner=unique("UIRegression"),unique("RoundHud")
local before,ownerBefore=live.Source,owner.Source
local function hash(source)
 local bytes=ENC:ComputeBufferHash(buffer.fromstring(source:gsub("\\r\\n","\\n")),Enum.HashAlgorithm.Sha256)
 local parts={{}}
 for index=0,buffer.len(bytes)-1 do parts[#parts+1]=string.format("%02x",buffer.readu8(bytes,index)) end
 return table.concat(parts)
end
local function guard()
 assert(unique("UIRegression")==live and unique("RoundHud")==owner,"original instance changed")
 assert(live.Source==before and SES:GetEditorSource(live)==before,"live UIRegression source/editor changed")
 assert(owner.Source==ownerBefore and SES:GetEditorSource(owner)==ownerBefore,"live RoundHud source/editor changed")
 assert(hash(before)=={luau_string(ui_hash)} and hash(ownerBefore)=={luau_string(hud_hash)},"repo/native source mismatch")
end
guard()
local probe=Instance.new("ModuleScript")
probe.Name="MongoTVCleanupN01Scenario_{label}"
local candidate={luau_string(source)}
local ok,result=pcall(function()
 assert(probe.Source=="" and SES:GetEditorSource(probe)=="","new probe must begin empty")
 SES:UpdateSourceAsync(probe,function(current)
  guard()
  assert(current=="" and probe.Source=="" and SES:GetEditorSource(probe)=="","temporary source baseline changed")
  return candidate
 end)
 assert(probe.Source==candidate and SES:GetEditorSource(probe)==candidate,"temporary source/editor mismatch")
 local answer,failed=require(probe).{entrypoint}()
 local decoded=HS:JSONDecode(answer)
 return {{answer=decoded,failed=failed}}
end)
local cleaned,cleanupError=pcall(function() probe:Destroy() end)
local stable,guardError=pcall(guard)
local output={{phase={luau_string(args.phase)},ok=ok,temporaryDestroyed=cleaned,
 originalSourcesUnchanged=stable,uiSha256={luau_string(ui_hash)},runtimeOwnerSha256={luau_string(hud_hash)},
 probeSha256={luau_string(hashlib.sha256(source.encode()).hexdigest())}}}
if ok then output.result=result else output.error=tostring(result) end
if not cleaned then output.cleanupError=tostring(cleanupError) end
if not stable then output.guardError=tostring(guardError) end
return HS:JSONEncode(output)
'''
    attempt = datetime.now(timezone.utc).strftime("%Y%m%dT%H%M%S%fZ")
    CHECKPOINT.mkdir(parents=True, exist_ok=True)
    (CHECKPOINT / f"B06-{receipt_label}-{attempt}.luau").write_text(code, encoding="utf8")
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, RELEASE_STUDIO_NAME, 15)
        result = client.call("execute_luau", {
            "studio_id": studio["id"], "datamodel_type": "Client", "code": code})
    finally:
        client.close()
    (CHECKPOINT / f"B06-{receipt_label}-{attempt}-result.json").write_text(result + "\n", encoding="utf8")
    with receipt_output.open("x", encoding="utf8") as output:
        output.write(result + "\n")
    value = unwrap(result)
    print(json.dumps(value, ensure_ascii=False))
    if not isinstance(value, dict) or not value.get("ok") or not value.get("temporaryDestroyed") or not value.get("originalSourcesUnchanged"):
        raise SystemExit(1)


if __name__ == "__main__":
    main()
