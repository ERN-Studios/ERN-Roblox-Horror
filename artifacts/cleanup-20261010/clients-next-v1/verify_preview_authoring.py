"""Execute actual current authoring guard text on immutable C06 sources.

No import of Studio helpers, Studio calls, production or manifest writes.
Historical dated sourcepacks remain byte-identical. Scope is the targeted
release edit and the old installer prefix, not either complete workflow.
"""
from pathlib import Path
import ast
import hashlib
import json
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[3]
ART = Path(__file__).resolve().parent
PROPOSAL = ART / "proposal-v1"
LUAU = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau.exe")
SHA = lambda raw: hashlib.sha256(raw).hexdigest()


def lua_literal(source):
    marker = "="
    while "]" + marker + "]" in source:
        marker += "="
    return "string.sub([" + marker + "[_" + source + "]" + marker + "],2)"


def evaluate(node, names):
    if isinstance(node, ast.Constant):
        return node.value
    if isinstance(node, ast.Name):
        return names[node.id]
    if isinstance(node, (ast.List, ast.Tuple)):
        return [evaluate(item, names) for item in node.elts]
    if isinstance(node, ast.BinOp) and isinstance(node.op, ast.Add):
        return evaluate(node.left, names) + evaluate(node.right, names)
    raise AssertionError("Only reviewed constant expression extraction is permitted")


def main():
    destination = ART / "authoring-gates-v1.json"
    assert not destination.exists(), "Immutable authoring receipt exists"
    proof = json.loads((PROPOSAL / "proposal.json").read_bytes())
    inputs = {phase: (PROPOSAL / (phase + ".source.luau")).read_bytes() for phase in ("before", "candidate")}
    assert all(SHA(raw) == proof[phase + "SHA256"] for phase, raw in inputs.items())
    release = ROOT / "tools/level6_playground/release_level6.py"
    release_raw = release.read_bytes()
    assignments = {node.targets[0].id: node.value for node in ast.parse(release_raw).body
                   if isinstance(node, ast.Assign) and len(node.targets) == 1 and isinstance(node.targets[0], ast.Name)}
    edits = evaluate(assignments["EDITS"], {"SSS": "ServerScriptService", "SPS": "StarterPlayer.StarterPlayerScripts",
                                          "OLD": "DevAccess.IsLevel6PreviewAllowed(player)", "NEW": "DevAccess.IsLevel6Allowed(player)"})
    selected = [edit for edit in edits if edit[0] == "StarterPlayer.StarterPlayerScripts.Level4PreviewPrompt"]
    assert len(selected) == 1
    path, old, new, count = selected[0]
    assert count == 1
    patch_template = ast.literal_eval(assignments["PATCH"])
    patch = patch_template % (lua_literal(path), lua_literal(old), lua_literal(new), count)
    installer = ROOT / "tools/level6_build/import/install_level6_gameplay.luau"
    installer_raw = installer.read_bytes()
    prefix = installer_raw.decode("utf8").split("local allowedNew = {", 1)[0]
    assert '"A Level 6 install target already exists"' in prefix
    assert "UpdateSourceAsync" not in prefix and ":GetAsync" not in prefix and "Instance.new" not in prefix
    manifest_raw = (ROOT / "studio-sync-manifest.json").read_bytes()
    manifest = json.loads(manifest_raw)
    existing = next(row for row in manifest["items"] if row["studioPath"] == "ServerScriptService.Level6PreviewAccess")
    assert existing["className"] == "Script"
    program = '''
local checks=0
local function check(value,message) checks+=1;assert(value,message) end
local function releaseGate(source)
 local target={Source=source}
 local game={StarterPlayer={StarterPlayerScripts={Level4PreviewPrompt=target}},GetService=function()error("Targeted release edit attempted native write",0)end}
 local result=(function()
''' + patch + '''
 end)()
 check(result=="already applied","actual release patch remains an idempotent skip")
 check(target.Source==source,"actual release patch does not replace reviewed source")
end
'''
    for raw in inputs.values():
        program += "releaseGate(" + lua_literal(raw.decode("utf8")) + ")\n"
    program += '''
local source={IsA=function(_,kind)return kind=="Folder"end,GetAttribute=function(_,key)return if key=="Ready" then true else "WornParty20260930-v2"end,
 FindFirstChild=function(_,name)check(name=="Meshes","old installer asks only for existing source mesh folder");return {GetChildren=function()return table.create(49,{})end}end}
local services={HttpService={},ScriptEditorService={},RunService={IsRunning=function()return false end},
 ServerScriptService={FindFirstChild=function(_,name)return if name=="Level6PreviewAccess" then {} else nil end},
 ServerStorage={FindFirstChild=function(_,name)return if name=="Level6BlenderSource" then source else nil end},
 StarterPlayer={FindFirstChild=function(_,name)return if name=="StarterPlayerScripts" then {FindFirstChild=function()return nil end} else nil end}}
local game={PlaceId=131311258779917,GameId=10559217407,GetService=function(_,name)
 check(services[name]~=nil,"old installer prefix asks only reviewed services")
 return services[name]
end}
local ok,err=pcall(function()
''' + prefix + '''
end)
check(not ok and tostring(err):find("A Level 6 install target already exists",1,true),"actual old installer refuses existing target before network or source writes")
print("AUTHORING_CHECKS="..checks)
'''
    with tempfile.TemporaryDirectory(prefix="preview-authoring-") as directory:
        path = Path(directory) / "actual-authoring-guards.luau"
        path.write_bytes(program.encode())
        result = subprocess.run([str(LUAU), str(path)], capture_output=True, text=True, timeout=30)
    assert result.returncode == 0, result.stdout + result.stderr
    assert release.read_bytes() == release_raw and installer.read_bytes() == installer_raw
    assert (ROOT / "studio-sync-manifest.json").read_bytes() == manifest_raw
    receipt = {"pass": True, "stdout": result.stdout, "programSHA256": SHA(program.encode()), "toolSHA256": SHA(Path(__file__).read_bytes()),
               "releaseToolPath": release.relative_to(ROOT).as_posix(), "releaseToolSHA256": SHA(release_raw),
               "installerPath": installer.relative_to(ROOT).as_posix(), "installerSHA256": SHA(installer_raw),
               "existingTargetRow": existing, "manifestSHA256": SHA(manifest_raw), "immutableInputHashes": {phase: SHA(raw) for phase, raw in inputs.items()},
               "nativeCalls": 0, "productionWrites": 0, "manifestWrites": 0,
               "scope": "Actual current release PATCH for only Level4PreviewPrompt is an idempotent skip before/after. Actual old installer prefix rejects the already-existing Level6PreviewAccess at its unchanged preflight. Explicit controlled service/world boundary tables; not full authoring or native install certification."}
    with destination.open("xb") as output:
        output.write((json.dumps(receipt, indent=2, ensure_ascii=False) + "\n").encode())
    print(json.dumps({"pass": True, "stdout": result.stdout, "nativeCalls": 0}))


if __name__ == "__main__":
    main()
