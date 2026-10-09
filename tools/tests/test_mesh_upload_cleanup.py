"""Offline resource/asset contracts for the real Blender upload helpers.

Runs their native Luau in the real interpreter. AssetService, vectors, encoding
and HTTP are fake boundaries; buffer parsing and all importer-generated code
are real. No live Studio connection, HTTP request, upload or repository write.
Use --baseline with --source-root pointing at before-source checkpoints to
record the original leaks without treating them as a passing cleanup gate.
"""

from __future__ import annotations

import argparse
import ast
import hashlib
import json
import math
import os
from pathlib import Path
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]
PLACE = 131311258779917
GROUP = 1039373905
WIRE = "encoded-mesh-one"
DIGEST = hashlib.sha256(WIRE.encode()).hexdigest()


def builder(source: str) -> str:
    assert source.count("local function build(b)") == 1
    assert source.count("local function run()") == 1
    return source[source.index("local function build(b)"):source.index("local function run()")]


def definitions(path: Path, names: set[str], namespace: dict) -> None:
    """Execute only exact, reviewed definitions, never top-level MCP setup."""
    tree = ast.parse(path.read_text(encoding="utf-8"), str(path))
    selected = [n for n in tree.body if isinstance(n, ast.FunctionDef) and n.name in names]
    assert {n.name for n in selected} == names
    exec(compile(ast.Module(selected, type_ignores=[]), str(path), "exec"), namespace)


def generated_codes(source_root: Path, scratch: Path) -> tuple[dict[str, dict], int]:
    l4 = (source_root / "tools/level4_blender/upload.luau").read_text(encoding="utf-8")
    l5 = (source_root / "tools/level5_import/upload.luau").read_text(encoding="utf-8")
    shared_builder = builder(l4)
    codes = {}
    checks = 0
    for name, source, prefix, uv in (("l4_manual", l4, "L4_Cinema_", True),
                                      ("l5_manual", l5, "L5_QuietSuburbs_", False)):
        code = source.replace("__LIMIT__", "10").replace("__ONLY__", "nil").replace("__BACKGROUND__", "false")
        codes[name] = {"code": code, "stage": [], "prefix": prefix, "uv": uv, "manual": True, "retries": True}

    # Execute the actual L1 upload function with an offline capture client and
    # temporary exports/results, including its wire-hash and receipt contracts.
    export = scratch / "export"
    (export / "chunks").mkdir(parents=True)
    (export / "chunks/c00001.b64").write_text(WIRE)
    ns = {"ROOT": source_root, "EXPORT": export, "RESULTS": export / "receipts.json",
          "PLACE": PLACE, "GROUP": GROUP, "hashlib": hashlib, "json": json}
    definitions(source_root / "tools/level1_blender/import_assets.py", {"upload"}, ns)

    class CaptureClient:
        def __init__(self):
            self.calls = []

        def _request(self, method, args, timeout):
            assert method == "tools/call" and args["name"] == "execute_luau"
            assert args["arguments"]["studio_id"] == "offline-only"
            assert args["arguments"]["datamodel_type"] == "Edit" and timeout == 900
            self.calls.append(args["arguments"]["code"])
            return {"result": {"content": [{"type": "text", "text": "1=7001"}]}}

    client, records = CaptureClient(), {}
    ns["upload"](client, "offline-only", {"chunks": [{"id": 1, "assetId": None, "wireSha256": DIGEST}]}, records)
    assert len(client.calls) == 1
    assert records == {"1": {"assetId": 7001, "wireSha256": DIGEST, "group": GROUP}}
    assert json.loads(ns["RESULTS"].read_text()) == records
    codes["l1_inline"] = {"code": client.calls[0], "stage": [], "prefix": "L1_ModularKit_", "uv": True,
                          "manual": False, "retries": False}
    checks += 4

    # L4 studio_upload has live top-level side effects. Evaluate only its real
    # two BUILD assignments and its one code-assignment expression, unchanged.
    path = source_root / "tools/level4_blender/studio_upload.py"
    tree = ast.parse(path.read_text(encoding="utf-8"), str(path))
    assignments = [n for n in tree.body if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == "BUILD" for t in n.targets)]
    assert len(assignments) == 2
    ns = {"HERE": str(source_root / "tools/level4_blender"), "os": os}
    exec(compile(ast.Module(assignments, type_ignores=[]), str(path), "exec"), ns)
    assert ns["BUILD"] == shared_builder
    expressions = [n for n in ast.walk(tree) if isinstance(n, ast.Assign)
                   and any(isinstance(t, ast.Name) and t.id == "code" for t in n.targets)]
    assert len(expressions) == 1
    ns.update(items='{1, "' + WIRE + '"}', GROUP=GROUP)
    exec(compile(ast.Module(expressions, type_ignores=[]), str(path), "exec"), ns)
    codes["l4_studio"] = {"code": ns["code"], "stage": [], "prefix": "L4_Cinema_v3_", "uv": True,
                          "manual": False, "retries": True}
    checks += 3

    # L2 remains unchanged; execute its exact helpers to exercise both inline
    # and persistent-slice extraction boundaries against the same L4 source.
    ns = {"ROOT": source_root, "PLACE_ID": PLACE, "GROUP_ID": GROUP, "MESH_BATCH_BYTES": 850000,
          "MESH_SLICE_CHARS": 8, "json": json, "math": math}
    definitions(ROOT / "tools/level2_blender/import_kit.py", {"lua", "require", "upload_code", "large_upload_codes"}, ns)
    inline = ns["upload_code"]([(DIGEST, WIRE)], {DIGEST: [1]})
    large = ns["large_upload_codes"](DIGEST, WIRE, 1)
    assert len(large) == 3 and all(len(c.encode()) < 850000 for c in large)
    codes["l2_inline"] = {"code": inline, "stage": [], "prefix": "L2K_Chunk_", "uv": True,
                          "manual": False, "retries": True, "digest": True}
    codes["l2_sliced"] = {"code": large[-1], "stage": large[:-1], "prefix": "L2K_Chunk_", "uv": True,
                          "manual": False, "retries": True, "digest": True, "sliced": True}
    checks += 1
    for name in ("l1_inline", "l4_studio", "l2_inline", "l2_sliced"):
        assert codes[name]["code"].count(shared_builder) == 1, name + " changed the extracted helper"
        checks += 1
    return codes, checks


PRELUDE = r'''
local checks = 0
local function check(condition, message)
    checks += 1
    assert(condition, message)
end
local function makeFixture(config)
    local state = {meshes={}, uploads={}, posts={}, events={}, waits={}, http=false}
    local Vector3 = {new=function(x,y,z) return {x,y,z} end}
    local Vector2 = {new=function(x,y) return {x,y} end}
    local Enum = {AssetType={Mesh="Mesh"}, AssetCreatorType={Group="Group"},
                  CreateAssetResult={Success="Success", UploadFailed="UploadFailed"}}
    local AS = {}
    function AS:CreateEditableMesh()
        if config.fail == "allocation" then error("fixture-allocation") end
        if config.fail == "allocation-nil" then return nil end
        local mesh = {destroyed=0, vertices={}, normals={}, uvs={}, triangles={}, faceNormals={}, faceUVs={}}
        table.insert(state.meshes, mesh)
        local function fail(name)
            if config.fail == name and (#state.meshes == 1 or not config.reenter) then error("fixture-"..name) end
            check(mesh.destroyed == 0, "use after Destroy")
        end
        function mesh:AddVertex(v) fail("AddVertex"); table.insert(self.vertices,v); return 100+#self.vertices end
        function mesh:AddNormal(v) fail("AddNormal"); table.insert(self.normals,v); return 200+#self.normals end
        function mesh:AddUV(v) fail("AddUV"); table.insert(self.uvs,v); return 300+#self.uvs end
        function mesh:AddTriangle(a,b,c) fail("AddTriangle"); table.insert(self.triangles,{a,b,c}); return 401 end
        function mesh:SetFaceNormals(f, ns) fail("SetFaceNormals"); self.faceNormals={f,ns} end
        function mesh:SetFaceUVs(f, us) fail("SetFaceUVs"); self.faceUVs={f,us} end
        function mesh:Destroy()
            self.destroyed += 1
            check(self.destroyed == 1, "double Destroy")
            check(not self.inFlight, "Destroy during CreateAssetAsync")
            table.insert(state.events,"destroy")
        end
        return mesh
    end
    function AS:CreateAssetAsync(mesh, kind, metadata)
        check(mesh.destroyed == 0, "upload of destroyed mesh")
        check(kind == "Mesh", "asset type changed")
        check(metadata.CreatorId == 1039373905 and metadata.CreatorType == "Group", "creator identity changed")
        check(metadata.Name == config.prefix .. "1" or metadata.Name == config.prefix .. "2", "asset name changed")
        check(metadata.Description == config.description .. (config.descriptionId and string.sub(metadata.Name,-1) or ""),
              "asset description changed")
        mesh.inFlight = true
        table.insert(state.events,"upload")
        table.insert(state.uploads,{mesh=mesh,metadata=metadata})
        mesh.inFlight = false
        if config.fail == "CreateAssetAsync" then error("fixture-CreateAssetAsync") end
        if config.fail == "upload-status" or (config.fail == "retry-success" and #state.uploads == 1) then
            return "UploadFailed", 0
        end
        return "Success", 7001
    end
    local function wire(uv)
        local b=buffer.create(if uv then 124 else 84)
        buffer.writeu32(b,0,3); buffer.writeu32(b,4,1)
        if uv then buffer.writeu32(b,8,3); buffer.writeu32(b,12,1) else buffer.writeu32(b,8,1) end
        local offset=if uv then 16 else 12
        for _,v in ipairs({{1,2,3},{4,5,6},{7,8,9},{0,1,0}}) do
            for _,value in ipairs(v) do buffer.writef32(b,offset,value); offset+=4 end
        end
        if uv then
            for _,v in ipairs({{0,0},{1,0},{0,1}}) do
                for _,value in ipairs(v) do buffer.writef32(b,offset,value); offset+=4 end
            end
            for _,value in ipairs({0,0,0,1,0,1,2,0,2}) do buffer.writeu32(b,offset,value); offset+=4 end
        else
            for _,value in ipairs({0,0,1,0,2,0}) do buffer.writeu32(b,offset,value); offset+=4 end
        end
        return b
    end
    local ENC = {}
    function ENC:Base64Decode(b)
        if config.fail == "decode" then error("fixture-decode") end
        check(buffer.tostring(b) == "encoded-mesh-one", "encoded wire changed")
        if config.fail == "header" then return buffer.create(0) end
        local result=wire(config.uv)
        if config.fail == "body" then
            local truncated=buffer.create(if config.uv then 16 else 12)
            buffer.copy(truncated,0,result,0,buffer.len(truncated))
            return truncated
        end
        return result
    end
    local HS = {HttpEnabled=config.httpEnabled or false}
    function HS:GetAsync(url, nocache)
        check(self.HttpEnabled == true and nocache == true, "HTTP authoring contract changed")
        if string.find(url,"/pending",1,true) then return if config.reenter then "1 2" else "1" end
        check(string.find(url,"/chunk/",1,true) ~= nil, "unexpected GET")
        return "encoded-mesh-one"
    end
    function HS:PostAsync(url, body)
        if not config.baseline then
            for _,mesh in ipairs(state.meshes) do check(mesh.destroyed == 1, "resource retained while registering result") end
        end
        table.insert(state.posts,{url=url,body=body})
        if config.fail == "registration" then error("fixture-registration") end
    end
    local function instance(class)
        local data={Name=class,ClassName=class,Value=""}
        local children,attrs={},{}
        local methods={}
        local self
        function methods:FindFirstChild(name) return children[name] end
        function methods:SetAttribute(key,value) attrs[key]=value end
        function methods:GetAttribute(key) return attrs[key] end
        function methods:Destroy() data.destroyed=true end
        self=setmetatable({}, {
            __index=function(_,key) return methods[key] or data[key] end,
            __newindex=function(_,key,value)
                data[key]=value
                if key=="Parent" and value then value._children[data.Name]=self end
            end,
        })
        data._children=children
        return self
    end
    local SS=instance("ServerStorage")
    local Instance={new=instance}
    local game={PlaceId=131311258779917}
    function game:GetService(name)
        return assert(({AssetService=AS,EncodingService=ENC,HttpService=HS,ServerStorage=SS})[name],name)
    end
    local shared={}
    local task={wait=function(seconds) table.insert(state.waits,seconds) end,
                spawn=function(callback) callback() end}
    return state,game,Vector3,Vector2,Enum,HS,shared,task,Instance
end
'''


DESCRIPTIONS = {
    "l4_manual": ("Level 4 cinema (Blender) import chunk ", True),
    "l5_manual": ("Level 5 Quiet Suburbs import chunk ", True),
    "l1_inline": ("Blender-built Level 1 yellow office kit", False),
    "l4_studio": ("Level 4 cinema v3 chunk ", True),
    "l2_inline": ("Level 2 Blender kit mesh " + DIGEST, False),
    "l2_sliced": ("Level 2 Blender kit mesh " + DIGEST, False),
}


def lua_case(name: str, flow: dict, failure: str, baseline: bool, *, reenter=False, http_enabled=False) -> str:
    description, description_id = DESCRIPTIONS[name]
    config = {"fail": failure, "prefix": flow["prefix"], "description": description,
              "descriptionId": description_id, "uv": flow["uv"], "reenter": reenter,
              "httpEnabled": http_enabled, "baseline": baseline}
    literal = "{" + ",".join(k + "=" + (str(v).lower() if isinstance(v, bool) else json.dumps(v)) for k,v in config.items()) + "}"
    stage = "\n".join("do\nlocal function stage()\n" + code + "\nend\nstage()\nend" for code in flow["stage"])
    uploaded = failure in ("", "retry-success", "upload-status", "CreateAssetAsync", "registration")
    success = failure in ("", "retry-success", "registration")
    if failure in ("decode", "header", "allocation", "allocation-nil"):
        allocated = 0
    else:
        allocated = 2 if reenter else 1
    expected_uploads = (4 if failure == "upload-status" and flow["retries"] else
                        2 if failure == "retry-success" and flow["retries"] else 1) if uploaded else (1 if reenter else 0)
    # Original L2 callers already cleaned thrown asset errors, but all original
    # builders leaked after partial construction. L1 and L4 callers also leaked
    # when CreateAssetAsync raised. Baseline asserts those observations honestly.
    original_leak = baseline and allocated and (
        (not uploaded) or (failure == "CreateAssetAsync" and name not in ("l2_inline", "l2_sliced")))
    destroyed = 0 if original_leak else 1
    lines = ["do", "local state,game,Vector3,Vector2,Enum,HS,shared,task,Instance=makeFixture("+literal+")", stage,
             "local function execute()\n"+flow["code"]+"\nend", "local ok,result=pcall(execute)",
             f'check(#state.meshes=={allocated}, "{name}/{failure}: allocations")',
             f'check(#state.uploads=={expected_uploads}, "{name}/{failure}: upload attempts")']
    for i in range(allocated):
        want = 1 if i > 0 else destroyed
        lines += [f'check(state.meshes[{i+1}].destroyed=={want}, "{name}/{failure}: exactly-once cleanup")']
    if uploaded and failure not in ("CreateAssetAsync",):
        lines += ['local mesh=state.uploads[1].mesh',
                  'check(#mesh.vertices==3 and #mesh.normals==1 and #mesh.triangles==1,"geometry counts")',
                  'check(mesh.vertices[2][1]==4 and mesh.vertices[3][3]==9,"vertex coordinates")',
                  'check(mesh.triangles[1][1]==101 and mesh.triangles[1][2]==102 and mesh.triangles[1][3]==103,"triangle identity")',
                  'check(mesh.faceNormals[1]==401 and mesh.faceNormals[2][1]==201 and mesh.faceNormals[2][3]==201,"face normals")']
        if flow["uv"]:
            lines += ['check(#mesh.uvs==3 and mesh.uvs[2][1]==1 and mesh.uvs[3][2]==1,"UV coordinates")',
                      'check(mesh.faceUVs[1]==401 and mesh.faceUVs[2][1]==301 and mesh.faceUVs[2][3]==303,"face UV identity")']
    if flow["manual"]:
        lines += ['check(ok,"manual wrapper return")',
                  f'check(HS.HttpEnabled=={str(http_enabled).lower()},"HttpEnabled restored")',
                  f'check(#state.posts=={2 if reenter else 1},"per-chunk registration count")']
        if success:
            lines += ['check(string.find(state.posts[1].url,"&asset=7001",1,true)~=nil,"valid AssetId registration")',
                      'check(state.posts[1].body=="","success registration body")']
        else:
            lines += ['check(string.find(state.posts[1].url,"&error=fail",1,true)~=nil,"failure registration")',
                      'check(#state.posts[1].body>0,"failure detail")']
        if failure == "registration":
            lines += ['check(string.find(result,"stopped:",1,true)~=nil,"registration error surfaced")',
                      'check(#state.uploads==1 and state.uploads[1].mesh.destroyed==1,"uploaded identity retained without second upload")']
        elif reenter:
            lines += ['check(string.find(state.posts[2].url,"&asset=7001",1,true)~=nil,"next chunk succeeds after failure")']
    elif flow.get("sliced"):
        lines += [f'check(ok=={str(success).lower()},"sliced exception contract")']
        if success:
            lines += [f'check(result=="{DIGEST}=7001","sliced result identity")',
                      f'check(game:GetService("ServerStorage"):FindFirstChild("__L2KMeshWire_{DIGEST[:16]}").destroyed==true,"scratch cleanup")']
        else:
            lines += [f'check(not game:GetService("ServerStorage"):FindFirstChild("__L2KMeshWire_{DIGEST[:16]}").destroyed,"failed scratch retained for recovery")']
    else:
        lines += ['check(ok,"inline result wrapper")']
        if success:
            key = DIGEST if flow.get("digest") else "1"
            lines += [f'check(result=="{key}=7001","inline result identity")']
        else:
            lines += ['check(string.find(result,"ERR:",1,true)~=nil,"inline error result")']
    if failure in ("AddVertex", "AddNormal", "AddUV", "AddTriangle", "SetFaceNormals", "SetFaceUVs", "CreateAssetAsync", "allocation", "decode"):
        message = "state.posts[1].body" if flow["manual"] else "tostring(result)"
        lines += [f'check(string.find({message},"fixture-{failure}",1,true)~=nil,"original error preserved")']
    lines += ['end']
    return "\n".join(lines)


def run(exe: Path, scratch: Path, source: str, filename: str) -> subprocess.CompletedProcess:
    path = scratch / filename
    path.write_text(source, encoding="utf-8")
    return subprocess.run([str(exe), str(path)], capture_output=True, encoding="utf-8", timeout=30)


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source-root", type=Path, default=ROOT)
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    exe = Path(os.environ.get("LUAU_BIN", ROOT / "tools/tests/luau"))
    assert exe.is_file(), "Set LUAU_BIN to the real Luau interpreter"
    with tempfile.TemporaryDirectory(prefix="mongotv-mesh-contract-") as temp:
        scratch = Path(temp)
        codes, python_checks = generated_codes(args.source_root, scratch)
        cases = []
        for name, flow in codes.items():
            failures = ["", "allocation", "allocation-nil", "decode", "header", "body", "AddVertex", "AddNormal",
                        "AddTriangle", "SetFaceNormals", "CreateAssetAsync", "upload-status"]
            if flow["uv"]:
                failures += ["AddUV", "SetFaceUVs"]
            if flow["retries"]:
                failures += ["retry-success"]
            if flow["manual"]:
                failures += ["registration"]
            for failure in failures:
                cases.append(lua_case(name, flow, failure, args.baseline))
            if flow["manual"]:
                cases.append(lua_case(name, flow, "AddTriangle", args.baseline, reenter=True))
                cases.append(lua_case(name, flow, "", args.baseline, http_enabled=True))
        source = PRELUDE + "\n" + "\n".join(cases) + '\nprint("native mesh assertions="..checks)\n'
        result = run(exe, scratch, source, "mesh_contract.luau")
        assert result.returncode == 0, result.stdout + result.stderr
        print(result.stdout.strip())
        print(f"mesh upload contract: {len(cases)} actual-Luau scenarios; {python_checks} Python wrapper/extraction checks")
        if args.baseline:
            print("BASELINE OBSERVATION: partial-build leaks and L1/L4 thrown-upload leaks reproduced; cleanup gate not passed")
        else:
            # A missing cleanup in the real extracted build helper must be
            # rejected by the independent resource-lifetime assertions.
            flow = dict(codes["l4_manual"])
            assert "em:Destroy()" in builder(flow["code"])
            flow["code"] = flow["code"].replace("em:Destroy()", "do end", 1)
            mutant = run(exe, scratch, PRELUDE + lua_case("l4_manual", flow, "AddTriangle", False), "mesh_cleanup_mutant.luau")
            assert mutant.returncode != 0 and "exactly-once cleanup" in mutant.stderr, mutant.stdout + mutant.stderr
            print("negative fixture: removing partial-build cleanup is rejected")
            for name in ("l1_inline", "l4_studio", "l4_manual", "l5_manual"):
                flow = dict(codes[name])
                offset = flow["code"].rindex("em:Destroy()")
                flow["code"] = flow["code"][:offset] + "do end" + flow["code"][offset + len("em:Destroy()"):]
                mutant = run(exe, scratch, PRELUDE + lua_case(name, flow, "CreateAssetAsync", False), name + "_mutant.luau")
                assert mutant.returncode != 0 and "exactly-once cleanup" in mutant.stderr, mutant.stdout + mutant.stderr
            print("negative fixtures: all four caller-owned thrown-upload cleanups are required")


if __name__ == "__main__":
    main()
