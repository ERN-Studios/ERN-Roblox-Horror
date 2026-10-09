"""Read exact task sources from authoritative Studio without editing it."""
import hashlib
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio, RELEASE_STUDIO_NAME
from push_repo_to_studio import luau_string

paths = sys.argv[2:]
label = sys.argv[1]
destination = ROOT / ".git" / "stutter-assets-20261009" / label
destination.mkdir(parents=True, exist_ok=False)
client = StudioMcpClient(find_mcp_batch())
records = []
try:
    client.initialize()
    studio = select_studio(client, RELEASE_STUDIO_NAME, 20)
    for path in paths:
        segments = "{" + ",".join(luau_string(p) for p in path.split(".")) + "}"
        resolve = f'''assert(game.PlaceId==131311258779917 and game.GameId==10559217407,"wrong place")
local s=game for _,n in {segments} do
 local found=nil for _,c in s:GetChildren() do if c.Name==n then assert(not found,"ambiguous path") found=c end end
 s=assert(found,"missing path")
end
local SES=game:GetService("ScriptEditorService")
assert(SES:GetEditorSource(s)==s.Source,"editor conflict")
'''
        metadata = resolve + '''local digest=game:GetService("EncodingService"):ComputeBufferHash(buffer.fromstring(s.Source),Enum.HashAlgorithm.Sha256)
local hex={} for i=0,buffer.len(digest)-1 do hex[i+1]=string.format("%02x",buffer.readu8(digest,i)) end
local props={Archivable=s.Archivable,LinkedSource=tostring(s.LinkedSource)}
if s:IsA("BaseScript") then props.Disabled=s.Disabled props.RunContext=tostring(s.RunContext) end
return game:GetService("HttpService"):JSONEncode({path=s:GetFullName(),class=s.ClassName,bytes=#s.Source,sha256=table.concat(hex),properties=props,attributes=s:GetAttributes(),placeVersion=game.PlaceVersion})'''
        args = {"studio_id": studio["id"], "datamodel_type": "Edit"}
        record = json.loads(client.call("execute_luau", dict(args, code=metadata)))
        chunks = []
        start = 1
        while start <= record["bytes"]:
            chunk_code = resolve + f'''local last=math.min({start}+23999,#s.Source)
while last<#s.Source and string.byte(s.Source,last+1)>=128 and string.byte(s.Source,last+1)<192 do last-=1 end
return game:GetService("HttpService"):JSONEncode({{text=string.sub(s.Source,{start},last),last=last}})'''
            chunk = json.loads(client.call("execute_luau", dict(args, code=chunk_code)))
            chunks.append(chunk["text"])
            start = chunk["last"] + 1
        source = "".join(chunks)
        assert hashlib.sha256(source.encode()).hexdigest() == record["sha256"], "source changed during read"
        assert json.loads(client.call("execute_luau", dict(args, code=metadata))) == record, "baseline changed"
        file = destination / (path.replace(".", "__") + ".luau")
        file.write_text(source, encoding="utf-8", newline="\n")
        record["sourceFile"] = str(file)
        records.append(record)
finally:
    client.close()
(destination / "sources.json").write_text(json.dumps(records, indent=2) + "\n", encoding="utf-8")
print(json.dumps({"destination": str(destination), "sources": len(records)}))
