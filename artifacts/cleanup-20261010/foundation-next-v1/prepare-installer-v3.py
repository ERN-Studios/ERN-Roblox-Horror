"""Prepare production-layout candidate only; never import/connect to Studio."""
from pathlib import Path
import hashlib
import json

HERE = Path(__file__).resolve().parent
ROOT = HERE.parents[2]
OUT = HERE / "installer-v3"
assert not OUT.exists(), "Immutable version already exists"
sha = lambda raw: hashlib.sha256(raw).hexdigest()
base = (HERE / "install_new_scripts.candidate-v2.py").read_bytes()
assert sha(base) == "40b1bef366922f18015411e6c665f4caec25a80f789ed173c1e27d44b179ea2a"
source = base.decode()

def replace(old, new):
    global source
    assert source.count(old) == 1, old[:120]
    source = source.replace(old, new)

end = source.index('"""', 3) + 3
source = '''"""Install explicitly selected authoring mirrors with fresh native compare-and-swap.

Studio remains authoritative. This manual tool defaults to refusing differing
existing Source; --overwrite is an explicit authoring operation against a fresh
Source/editor/identity/class/property/attribute/tag baseline, checked again in
the UpdateSourceAsync callback. No raw Source setter, bulk sync or mode switch.

Missing targets use a fresh owned empty LuaSourceContainer; callback and cleanup
checks preserve concurrently created or modified objects. Fresh native metadata
is registered only after verification. Registration is separate from native
mutation: a final conflict can leave a successfully installed owned Source with
the old manifest, reported as a failure for current-native reconciliation.

    python tools/install_new_scripts.py --dry-run <mirror path> [...]
    python tools/install_new_scripts.py <mirror path> [...]

Source reads are bounded to 64 lines / 8 kB per native response. Write payloads
retain the existing single-literal request; no large native-write certification.
"""''' + source[end:]
replace('import argparse\n', 'import argparse\nimport copy\nimport os\nimport types\n')
replace('sys.path.insert(0, str(Path(__file__).resolve().parents[3] / "tools"))  # Candidate location only',
        'sys.path.insert(0, str(Path(__file__).resolve().parent))')
replace('ROOT = Path(__file__).resolve().parents[3]  # Candidate location only',
        'ROOT = Path(__file__).resolve().parents[1]')
replace('    read_native_record, native_metadata_code, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)',
        '    native_metadata_code, validate_native_metadata, require_edit_state, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)')
replace('from push_repo_to_studio import luau_string', 'from push_repo_to_studio import luau_string, read_studio_source')
replace('from studio_source_contract import normalize, refresh_trailing_newline_metadata, sha256_of',
        'from studio_source_contract import canonical_bytes, normalize, refresh_trailing_newline_metadata, sha256_of')
replace('local parent=game\nfor index=1,#names-1 do parent=assert(child(parent,names[index]),"Missing installer parent") end',
'''local function resolveParent()
 local value=game
 for index=1,#names-1 do value=assert(child(value,names[index]),"Missing installer parent") end
 return value
end
local parent=resolveParent()''')
start = source.index('def lua_create(')
end = source.index('\ndef native_read(', start)
source = source[:start] + r'''def lua_create(path: str, source: str, kind: str, parent_id: str) -> str:
    # The only writable object is created by this call, never looked up as an
    # overwrite fallback. Parent-path/identity races refuse inside the callback.
    return path_guard(path) + r"""
assert(current==nil,"Installer target appeared")
assert(parent:GetDebugId(16)==__PARENT__,"Installer parent changed")
local owned=Instance.new(__CLASS__)
local ownedId=owned:GetDebugId(16)
local attached=false
local initialEnabled=nil
local initialProps={Archivable=owned.Archivable,LinkedSource=owned.LinkedSource}
if __CLASS__~="ModuleScript" then
 initialEnabled=owned.Enabled
 initialProps.Enabled=owned.Enabled;initialProps.Disabled=owned.Disabled;initialProps.RunContext=owned.RunContext
end
local expectedProps=table.clone(initialProps)
local expectedName=owned.Name
local function identity()
 return owned.ClassName==__CLASS__ and owned:GetDebugId(16)==ownedId and owned.Name==expectedName
end
local function ownFields(allowedSource)
 if not identity() then return false end
 for key,value in expectedProps do if owned[key]~=value then return false end end
 return owned.Source==allowedSource and SES:GetEditorSource(owned)==allowedSource
  and next(owned:GetAttributes())==nil and #game:GetService("CollectionService"):GetTags(owned)==0
end
local function ownedState(allowedSource)
 return resolveParent()==parent and parent:GetDebugId(16)==__PARENT__
  and owned.Parent==parent and child(parent,names[#names])==owned and ownFields(allowedSource)
end
local ok,err=pcall(function()
 assert(owned.Source=="" and SES:GetEditorSource(owned)=="","New script not empty")
 expectedName=names[#names];owned.Name=expectedName
 if initialEnabled~=nil then
  expectedProps.Enabled=false;expectedProps.Disabled=true;owned.Enabled=false
 end
 assert(owned.Parent==nil and ownFields(""),"Fresh owned setup changed")
 assert(resolveParent()==parent and parent:GetDebugId(16)==__PARENT__,"Installer parent changed")
 assert(child(parent,names[#names])==nil,"Installer target appeared")
 owned.Parent=parent;attached=true
 SES:UpdateSourceAsync(owned,function(old)
  assert(not RS:IsRunning() and game.PlaceId==131311258779917 and game.GameId==10559217407,"Native mode/place changed")
  assert(old=="" and ownedState(""),"Owned new script changed")
  return __SOURCE__
 end)
 assert(ownedState(__SOURCE__),"Owned script landing changed")
 if initialEnabled~=nil then
  expectedProps.Enabled=initialEnabled;expectedProps.Disabled=not initialEnabled
  owned.Enabled=initialEnabled
 end
 assert(ownedState(__SOURCE__),"Owned script final state changed")
end)
if not ok then
 -- Parent=nil is not unconditional deletion authority. Once attached, any
 -- foreign move is retained; unknown getter outcomes retain the object too.
 local clean,problem=pcall(function()
  local ownedParent=(not attached and owned.Parent==nil) or
   (attached and owned.Parent==parent and resolveParent()==parent and parent:GetDebugId(16)==__PARENT__
    and child(parent,names[#names])==owned)
  if ownedParent and (ownFields("") or ownFields(__SOURCE__)) then owned:Destroy() end
 end)
 if not clean then error(tostring(err).."; owned cleanup unknown, preserved: "..tostring(problem)) end
 error(err)
end
return "ok"
""".replace("__PARENT__", luau_string(parent_id)).replace("__CLASS__", luau_string(kind)).replace("__SOURCE__", luau_string(source))

''' + source[end:]
start = source.index('def native_read(')
end = source.index('\ndef stable_metadata(', start)
source = source[:start] + '''def native_read(client, sid, path, kind):
    """Use the S13 getter/schema and real reader in an isolated bounded namespace."""
    segments = path.split(".")
    code = native_metadata_code(segments, kind, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)
    namespace = {**read_studio_source.__globals__, "READ_CHUNK_LINES": 64}
    reader = types.FunctionType(read_studio_source.__code__, namespace)
    class BoundedClient:
        def call(self, tool, arguments=None):
            response = client.call(tool, arguments)
            if not isinstance(response, str):
                raise StudioMcpError("Unreadable installer native response")
            source_chunk = tool == "execute_luau" and "local first, count =" in (arguments or {}).get("code", "")
            limit = 8000 if source_chunk else 20000
            if len(response.encode("utf8")) > limit:
                raise StudioMcpError("Installer native response exceeds bounded transport")
            return response
    bounded = BoundedClient()
    def capture():
        try:
            value = json.loads(bounded.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code}))
        except (ValueError, TypeError) as error:
            raise StudioMcpError("Unreadable native metadata response") from error
        if isinstance(value, dict) and value.get("attributes") == []:
            value["attributes"] = {}
        validate_native_metadata(value, segments, kind, EXPECTED_PLACE_ID, EXPECTED_UNIVERSE_ID)
        return value
    require_edit_state(bounded, sid)
    before = capture()
    source = reader(bounded, sid, segments)
    after = capture()
    require_edit_state(bounded, sid)
    if before != after:
        raise StudioMcpError("Native Source/identity/properties/attributes/tags changed during chunk read")
    if len(canonical_bytes(source)) != before["canonicalBytes"] or sha256_of(source) != before["sourceSHA256"]:
        raise StudioMcpError("Native metadata/chunk Source hash mismatch")
    return source, before


def presence_read(client, sid, path):
    try:
        response = client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)})
        if not isinstance(response, str) or len(response.encode("utf8")) > 20000:
            raise StudioMcpError("Unreadable installer presence")
        value = json.loads(response)
    except (ValueError, TypeError) as error:
        raise StudioMcpError("Unreadable installer presence") from error
    if not isinstance(value, dict) or set(value) != {"missing", "parentId"} or type(value["missing"]) is not bool or not isinstance(value["parentId"], str) or not value["parentId"]:
        raise StudioMcpError("Invalid installer presence/parent identity")
    return value


def register_manifest(path, before, value):
    """Immediate byte CAS and atomic replace, not a cross-process lock."""
    encoded = (json.dumps(value, indent=2, ensure_ascii=False) + "\\n").encode("utf8")
    temporary = path.with_name(path.name + ".installer-owned.tmp")
    if temporary.exists():
        raise StudioMcpError("Existing installer temp file preserved")
    try:
        with temporary.open("xb") as stream:
            stream.write(encoded)
        if path.read_bytes() != before:
            raise StudioMcpError("Manifest changed before atomic registration; preserve it")
        os.replace(temporary, path)
        if path.read_bytes() != encoded:
            raise StudioMcpError("Manifest changed after registration; preserve current bytes")
    finally:
        if temporary.exists(): temporary.unlink()

''' + source[end:]
replace('presence = json.loads(client.call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": lua_lookup(path)}))',
        'presence = presence_read(client, sid, path)')
replace('            item = {"studioPath": path,',
'''            previous = [row for row in manifest["items"] if row.get("file") == file]
            item = copy.deepcopy(previous[0]) if previous else {}
            item.pop("studioTrailingNewline", None)
            item.update({"studioPath": path,''')
replace('"sourceEditorMatches": native["sourceEditorMatches"]}', '"sourceEditorMatches": native["sourceEditorMatches"]})')
replace('            manifest_path.write_text(json.dumps(manifest, indent=2, ensure_ascii=False) + "\\n", encoding="utf-8")',
'''            try:
                register_manifest(manifest_path, manifest_bytes, manifest)
            except (StudioMcpError, OSError) as error:
                print(f"FAILED {path}: {error}")
                failures += 1
                break''')
replace('    targeted = {file for file, _, _ in plans}',
'''    targeted = {file for file, _, _ in plans}
    for file in targeted:
        if sum(item.get("file") == file for item in manifest.get("items", [])) > 1:
            raise StudioMcpError("Duplicate targeted manifest rows; no write")''')
tools = OUT / "tools"
tools.mkdir(parents=True)
(OUT / ".gitattributes").write_bytes(b"* -text\n")
(tools / "install_new_scripts.py").write_bytes(source.encode())
dependencies = {}
for name in ("sync_from_studio.py", "push_repo_to_studio.py", "studio_source_contract.py"):
    raw = (ROOT / "tools" / name).read_bytes()
    (tools / name).write_bytes(raw)
    dependencies[name] = {"bytes": len(raw), "sha256": sha(raw)}
receipt = {"schema": "generic-installer-production-layout-candidate-v3", "nativeCalls": 0,
    "productionWrites": 0, "manifestWrites": 0, "indexWrites": 0,
    "baseCandidateSHA256": sha(base), "candidateSHA256": sha(source.encode()),
    "productionInstallerSHA256": sha((ROOT / "tools/install_new_scripts.py").read_bytes()),
    "dependenciesCopiedByteExact": dependencies,
    "scope": "Candidate-only isolated project/tools production path layout. Fresh native metadata/CAS, strict presence, safe owned create/cleanup, bounded read namespace, preserved unknown target fields and immediate manifest CAS. No native or large write transport certification."}
(OUT / "preparation.json").write_bytes((json.dumps(receipt, indent=2) + "\n").encode())
print(json.dumps({"candidateBytes": len(source.encode()), "candidateSHA256": sha(source.encode()), "nativeCalls": 0}))
