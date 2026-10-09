"""S09: one-way, exact one-script Studio export; no native writes or mode changes.

Root owns staging/commit. Preserve every other working manifest row and emit a
separate HEAD + S03 Ambience + S09 General Sound manifest for scoped staging.
"""
from pathlib import Path
import ast
import copy
import hashlib
import json
import os
import subprocess
import sys
import tempfile

sys.dont_write_bytecode = True
ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio
from studio_source_contract import canonical_bytes

DEST = ROOT / "artifacts/cleanup-serverstorage-20261009/S09-general-sound-v1"
TARGET = "StarterPlayer/StarterPlayerScripts/SoundController.LocalScript.lua"
STUDIO_PATH = "StarterPlayer.StarterPlayerScripts.SoundController"
AMBIENCE = "StarterPlayer/StarterPlayerScripts/Level 2 Poolrooms Ambience.LocalScript.lua"
LEVEL2 = "StarterPlayer/StarterPlayerScripts/Level 2 Sound Controller.LocalScript.lua"
SID = "1b603e69-7ae1-4572-b210-d5bf05c684ff"
COMPILER = Path("C:/Users/mikke/AppData/Local/Temp/codex-luau-0.737/luau-compile.exe")
CHUNK = 12000

GUARD = '''local H=game:GetService("HttpService")
local SES=game:GetService("ScriptEditorService")
local ENC=game:GetService("EncodingService")
local function mode()
 assert(not game:GetService("RunService"):IsRunning(),"S09 requires Edit; never switch modes")
 assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"Unexpected place/universe")
end
local function sha(text)
 local digest=ENC:ComputeBufferHash(buffer.fromstring(text),Enum.HashAlgorithm.Sha256)
 local out={} for i=0,buffer.len(digest)-1 do out[#out+1]=string.format("%02x",buffer.readu8(digest,i)) end
 return table.concat(out)
end
local function stable(v)
 if type(v)~="table" then return H:JSONEncode(v) end
 local keys={} for key in v do keys[#keys+1]=key end
 table.sort(keys,function(a,b)return tostring(a)<tostring(b)end)
 local out={} for _,key in keys do out[#out+1]=H:JSONEncode(key)..":"..stable(v[key]) end
 return "{"..table.concat(out,",").."}"
end
local function resolve()
 local node=game
 for _,name in {"StarterPlayer","StarterPlayerScripts","SoundController"} do
  local found=nil for _,child in node:GetChildren() do
   if child.Name==name then assert(found==nil,"Ambiguous S09 path");found=child end
  end
  node=assert(found,"Missing S09 path")
 end
 assert(node.ClassName=="LocalScript" and node:GetFullName()=="StarterPlayer.StarterPlayerScripts.SoundController","Unexpected S09 instance")
 return node
end
local function read(pin)
 mode()
 local node=resolve()
 local source=node.Source local editor=SES:GetEditorSource(node)
 assert(source==editor,"Native/editor conflict; leave both unchanged")
 local attrs=node:GetAttributes()
 for name,value in attrs do
  local kind=typeof(value)
  assert(kind=="string" or kind=="boolean" or kind=="number","Unsupported S09 attribute type; do not lose typed data: "..name)
 end
 local tags=node:GetTags() table.sort(tags)
 local meta={path=node:GetFullName(),className=node.ClassName,instanceId=node:GetDebugId(16),
  parentId=node.Parent:GetDebugId(16),parentPath=node.Parent:GetFullName(),parentClass=node.Parent.ClassName,
  rawBytes=#source,rawSourceSHA256=sha(source),editorMatches=true,
  properties={Enabled=node.Enabled,Disabled=node.Disabled,RunContext=tostring(node.RunContext),LinkedSource=node.LinkedSource,Archivable=node.Archivable},
  attributes=attrs,tags=tags}
 if pin then assert(stable(meta)==stable(pin),"S09 exact Source/editor/identity/properties/attrs/tags changed") end
 assert(node.Source==source and SES:GetEditorSource(node)==source,"S09 Source/editor changed within read")
 mode()
 return source,meta
end
'''


def sha(raw):
    return hashlib.sha256(raw).hexdigest()


def new(path, raw):
    path.parent.mkdir(parents=True, exist_ok=True)
    with path.open("xb") as stream:
        assert stream.write(raw) == len(raw)
    assert path.read_bytes() == raw


def literal(value):
    text = json.dumps(value, ensure_ascii=False, separators=(",", ":"))
    assert "]========]" not in text
    return "[========[" + text + "]========]"


def row_for(manifest, file):
    matches = [row for row in manifest["items"] if row.get("file") == file]
    assert len(matches) == 1, "Missing/duplicate manifest row: " + file
    return matches[0]


def one_row_blob(raw, file, replacement):
    """Splice just the row; preserve every unrelated raw byte and metadata."""
    text = raw.decode("utf-8")
    decoder = json.JSONDecoder()
    pos = text.index('"items":') + len('"items":')
    while text[pos].isspace(): pos += 1
    assert text[pos] == "["
    pos += 1
    while True:
        while text[pos].isspace() or text[pos] == ",": pos += 1
        if text[pos] == "]": break
        start = pos
        row, pos = decoder.raw_decode(text, pos)
        if row.get("file") == file:
            newline = "\r\n" if "\r\n" in text[start:pos] else "\n"
            replacement_text = json.dumps(replacement, indent=2, ensure_ascii=False).replace("\n", newline + "    ")
            result = (text[:start] + replacement_text + text[pos:]).encode("utf-8")
            old = json.loads(raw); after = json.loads(result)
            assert row_for(old, file) == row
            assert row_for(after, file) == replacement
            row_for(after, file).clear(); row_for(old, file).clear()
            assert after == old, "Unrelated manifest data changed"
            return result
    raise AssertionError("Target manifest row not found")


def replace_exact(path, before, after):
    assert path.read_bytes() == before, "Concurrent local edit: " + str(path)
    fd, name = tempfile.mkstemp(prefix=".mongotv-s09-", dir=path.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "wb") as stream: assert stream.write(after) == len(after)
        assert temporary.read_bytes() == after
        assert path.read_bytes() == before, "Concurrent local edit before replacement"
        os.replace(temporary, path)
    finally:
        temporary.unlink(missing_ok=True)


def main():
    assert not DEST.exists(), "Use an immutable new capture destination"
    before = (ROOT / TARGET).read_bytes()
    head = subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip()
    head_source = subprocess.check_output(["git", "show", "HEAD:" + TARGET], cwd=ROOT)
    assert canonical_bytes(before.decode()) == canonical_bytes(head_source.decode()), "General Sound local file is dirty; preserve it"
    manifest_path = ROOT / "studio-sync-manifest.json"
    manifest_before = manifest_path.read_bytes()
    head_manifest_raw = subprocess.check_output(["git", "show", "HEAD:studio-sync-manifest.json"], cwd=ROOT)
    working = json.loads(manifest_before)
    s03 = json.loads((ROOT / ".git/mongotv-cleanup-20261009/s03-ambience-before/export-preparation.json").read_bytes())["entry"]
    assert row_for(working, AMBIENCE) == s03
    assert sha(canonical_bytes((ROOT / AMBIENCE).read_text(encoding="utf-8"))) == s03["sha256"]
    row_for(working, TARGET)
    DEST.mkdir(parents=True)
    new(DEST / ".gitattributes", b"* -text -whitespace\n")
    new(DEST / "repo-before.raw.lua", before)
    new(DEST / "manifest-working-before.bin", manifest_before)
    new(DEST / "manifest-head-before.bin", head_manifest_raw)
    new(DEST / "S03-ambience-row.json", (json.dumps(s03, indent=2) + "\n").encode())
    new(DEST / "export-helper-source.py", Path(__file__).read_bytes())
    new(DEST / "native-read-guard.luau", GUARD.encode())
    report = {"schema": "s09-general-sound-downstream-export-v1", "pass": False,
              "nativeSourceWrites": 0, "nativePropertyWrites": 0, "modeSwitches": 0,
              "target": TARGET, "headCommit": head, "studioId": SID,
              "repoBeforeRawSHA256": sha(before), "headManifestRawSHA256": sha(head_manifest_raw),
              "workingManifestBeforeRawSHA256": sha(manifest_before), "compiled": []}
    client = None
    changed = []
    after_source = manifest_after = None
    primary = None
    try:
        client = StudioMcpClient(find_mcp_batch())
        client.initialize()
        studio = select_studio(client, "[UPDATE] BACKROOMS: STAY QUIET", 20)
        assert (studio.get("studio_id") or studio.get("id")) == SID

        def call(suffix):
            output = client.call("execute_luau", {"studio_id": SID, "datamodel_type": "Edit", "code": GUARD + suffix})
            assert len(output.encode("utf-8")) < 32000, "Bounded S09 response exceeded"
            return json.loads(output)

        begin = call('local source,meta=read(nil) return H:JSONEncode(meta)')
        new(DEST / "native-before.json", (json.dumps(begin, indent=2) + "\n").encode())
        blocks = []
        for offset in range(0, begin["rawBytes"], CHUNK):
            piece = call('local source,meta=read(H:JSONDecode(' + literal(begin) + '))\n'
                         + f'local piece=source:sub({offset + 1},{offset + CHUNK}) local out={{}} '
                         + 'for i=1,#piece do out[i]=string.format("%02x",string.byte(piece,i)) end '
                         + f'return H:JSONEncode({{offset={offset},bytes=#piece,hex=table.concat(out)}})')
            block = bytes.fromhex(piece["hex"])
            assert piece["offset"] == offset and piece["bytes"] == len(block) == min(CHUNK, begin["rawBytes"] - offset)
            blocks.append(block)
        native = b"".join(blocks)
        assert len(native) == begin["rawBytes"] and sha(native) == begin["rawSourceSHA256"]
        native.decode("utf-8")
        new(DEST / "Source.raw.lua", native)
        after_source = canonical_bytes(native.decode())
        new(DEST / "Source.canonical.lua", after_source)
        for name in ("repo-before.raw.lua", "Source.raw.lua"):
            for optimization in ("-O0", "-O1"):
                result = subprocess.run([str(COMPILER), "--binary", "-g0", optimization, str(DEST / name)], capture_output=True, timeout=30)
                assert result.returncode == 0, result.stderr.decode(errors="replace")
                report["compiled"].append({"file": name, "optimization": optimization, "exitCode": 0,
                                           "compilerSHA256": sha(COMPILER.read_bytes()), "outputSHA256": sha(result.stdout)})
        end = call('local source,meta=read(H:JSONDecode(' + literal(begin) + ')) return H:JSONEncode(meta)')
        assert end == begin
        new(DEST / "native-after-capture.json", (json.dumps(end, indent=2) + "\n").encode())
        entry = copy.deepcopy(row_for(working, TARGET))
        entry.update(bytes=len(after_source), sha256=sha(after_source), status="synced", sourceEditorMatches=True,
                     properties=begin["properties"], attributes=begin["attributes"], tags=begin["tags"])
        entry.pop("studioTrailingNewline", None)
        manifest_after = one_row_blob(manifest_before, TARGET, entry)
        new(DEST / "manifest-working-S09-proposal.bin", manifest_after)
        scoped = json.loads(head_manifest_raw)
        assert scoped["placeId"] == 131311258779917 and scoped["universeId"] == 10559217407
        matching = [row for row in scoped["items"] if row.get("file") == AMBIENCE]
        assert not matching, "S03 already in HEAD; root must reconcile intentionally"
        insertion = next(i for i, row in enumerate(scoped["items"])
                         if row.get("file") == "StarterPlayer/StarterPlayerScripts/Level 2 Slide Controller.LocalScript.lua")
        scoped["items"].insert(insertion, copy.deepcopy(s03))
        scoped["counts"]["scripts"] += 1
        scoped["counts"]["total"] += 1
        head_target = row_for(scoped, TARGET)
        head_target.clear(); head_target.update(copy.deepcopy(entry))
        assert row_for(scoped, LEVEL2) == row_for(json.loads(head_manifest_raw), LEVEL2), "Actor Level2Sound accidentally included"
        unchanged = copy.deepcopy(scoped)
        unchanged["items"].remove(row_for(unchanged, AMBIENCE))
        target_prior = copy.deepcopy(row_for(json.loads(head_manifest_raw), TARGET))
        unchanged_target = row_for(unchanged, TARGET)
        unchanged_target.clear(); unchanged_target.update(target_prior)
        unchanged["counts"]["scripts"] -= 1
        unchanged["counts"]["total"] -= 1
        assert unchanged == json.loads(head_manifest_raw), "Unrelated HEAD rows/order/metadata changed"
        scoped_blob = (json.dumps(scoped, indent=2) + "\n").encode()
        new(DEST / "manifest-head-S03-S09-scoped.bin", scoped_blob)
        assert subprocess.check_output(["git", "rev-parse", "HEAD"], cwd=ROOT).decode().strip() == head
        assert (ROOT / TARGET).read_bytes() == before and manifest_path.read_bytes() == manifest_before
        replace_exact(ROOT / TARGET, before, after_source); changed.append(TARGET)
        replace_exact(manifest_path, manifest_before, manifest_after); changed.append("studio-sync-manifest.json")
        final = call('local source,meta=read(H:JSONDecode(' + literal(begin) + ')) return H:JSONEncode(meta)')
        assert final == begin
        assert (ROOT / TARGET).read_bytes() == after_source and manifest_path.read_bytes() == manifest_after
        new(DEST / "native-final.json", (json.dumps(final, indent=2) + "\n").encode())
        report.update(pass_=True, nativeSourceRawSHA256=sha(native), canonicalSourceSHA256=sha(after_source),
                      nativeBytes=len(native), canonicalBytes=len(after_source), nativeEditorParity=True,
                      allOtherManifestRawBytesPreserved=True, allOtherManifestRowsPreserved=True,
                      workingManifestAfterSHA256=sha(manifest_after), scopedCommitManifestSHA256=sha(scoped_blob),
                      scopedCommitManifestFile=(DEST / "manifest-head-S03-S09-scoped.bin").relative_to(ROOT).as_posix(),
                      scopedRows=[AMBIENCE, TARGET], actorLevel2SoundExcluded=True, changedLocalFiles=changed,
                      gameplayPassed=False, fullRepoStudioParityClaimed=False)
    except BaseException as error:
        primary = error
        report["error"] = str(error)
        report["rollback"] = []
        for name in reversed(changed):
            path = ROOT / name
            owned = after_source if name == TARGET else manifest_after
            prior = before if name == TARGET else manifest_before
            try:
                if path.read_bytes() != owned:
                    report["rollback"].append({"path": name, "foreignEditPreserved": True})
                    continue
                replace_exact(path, owned, prior)
                report["rollback"].append({"path": name, "restoredOwnWrite": True})
            except BaseException as recovery:
                error.add_note("S09 own rollback: " + str(recovery))
        raise
    finally:
        if client is not None:
            try: client.close()
            except BaseException as cleanup:
                if primary is not None: primary.add_note("S09 MCP close: " + str(cleanup))
                else: report["closeError"] = str(cleanup); report["pass_"] = False
        report["pass"] = report.pop("pass_", False)
        new(DEST / "export-result.json", (json.dumps(report, indent=2) + "\n").encode())
    assert report["pass"], report
    print(json.dumps({key:report[key] for key in ("pass","target","nativeSourceRawSHA256","canonicalSourceSHA256","nativeBytes","scopedCommitManifestSHA256","scopedCommitManifestFile","nativeSourceWrites")}))


if __name__ == "__main__":
    main()
