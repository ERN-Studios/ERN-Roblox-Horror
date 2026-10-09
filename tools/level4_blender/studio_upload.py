# Upload the exported chunks to Roblox without HTTP (today's Studio MCP sandbox has no Network capability):
# each execute_luau call carries up to ~900 KB of chunk base64 in the code, builds EditableMeshes and calls
# AssetService:CreateAssetAsync. Results append to results.jsonl ({"id", "asset", "h"}) like serve.py did.
#   python studio_upload.py [export_dir] [--reuse hashmap.json ...] [--limit N]
# --reuse: json files {sha256: asset_id} (or results.jsonl files with "h"); chunks whose content hash matches are
# recorded without uploading.
import hashlib, json, os, sys, time

sys.path.insert(0, r"G:\Roblox\MongoTV\tools")
import sync_from_studio as s

HERE = r"G:\Roblox\MongoTV\tools\level4_blender"
RESULTS = os.path.join(HERE, "results.jsonl")
args = sys.argv[1:]
EXPORT = args[0] if args and not args[0].startswith("--") else r"G:\Roblox\_local\l4blender\export"
LIMIT = int(args[args.index("--limit") + 1]) if "--limit" in args else 10 ** 9
BATCH = 900_000
GROUP = 1039373905

reuse = {}
if "--reuse" in args:
    for f in args[args.index("--reuse") + 1:]:
        if f.startswith("--"):
            break
        if f.endswith(".jsonl"):
            for line in open(f):
                r = json.loads(line)
                if r.get("asset") and r.get("h"):
                    reuse[r["h"]] = r["asset"]
        else:
            reuse.update(json.load(open(f)))

done = {}
if os.path.exists(RESULTS):
    for line in open(RESULTS):
        r = json.loads(line)
        if r.get("asset"):
            done[r["id"]] = r["asset"]

manifest = json.load(open(os.path.join(EXPORT, "manifest.json")))
ids = [c["id"] for c in manifest["chunks"] if c["id"] not in done]
out = open(RESULTS, "a")
todo = []
for cid in ids:
    b64 = open(os.path.join(EXPORT, "chunks", "c%05d.b64" % cid)).read().strip()
    h = hashlib.sha256(b64.encode()).hexdigest()
    if h in reuse:
        out.write(json.dumps({"id": cid, "asset": reuse[h], "h": h, "reused": True}) + "\n")
        continue
    todo.append((cid, b64, h))
out.flush()
print("pending", len(ids), "reused", len(ids) - len(todo), "to upload", len(todo), flush=True)

BUILD = open(os.path.join(HERE, "upload.luau"), encoding="utf-8").read()
BUILD = BUILD[BUILD.index("local function build(b)"):BUILD.index("local function run()")]

c = s.StudioMcpClient(s.find_mcp_batch())
c.initialize()


def call(tool, a, timeout=1800):
    r = c._request("tools/call", {"name": tool, "arguments": a}, timeout=timeout)
    res = r.get("result", {})
    return "\n".join(b.get("text", "") for b in res.get("content", []) if b.get("type") == "text"), res.get("isError")


for i in range(30):
    t, e = call("list_roblox_studios", {}, 30)
    if not e and '"studios"' in t:
        break
    time.sleep(1)
st = json.loads(t)["studios"]
sid = ([x for x in st if "BACKROOMS" in (x.get("name") or "")] or st)[0]["id"]

batches, cur, size = [], [], 0
for item in todo[:LIMIT]:
    if cur and size + len(item[1]) > BATCH:
        batches.append(cur); cur, size = [], 0
    cur.append(item); size += len(item[1])
if cur:
    batches.append(cur)

n = 0
for bi, batch in enumerate(batches):
    items = ",\n".join('{%d, "%s"}' % (cid, b64) for cid, b64, _ in batch)
    code = ("local AS = game:GetService(\"AssetService\")\nlocal ENC = game:GetService(\"EncodingService\")\n" + BUILD +
            "\nlocal ITEMS = {\n" + items + "\n}\nlocal out = {}\nfor _, it in ipairs(ITEMS) do\n"
            "  local ok, res = pcall(function()\n"
            "    local em = build(ENC:Base64Decode(buffer.fromstring(it[2])))\n"
            "    local status, assetId\n"
            "    for attempt = 1, 4 do\n"
            "      status, assetId = AS:CreateAssetAsync(em, Enum.AssetType.Mesh, {Name = \"L4_Cinema_v3_\" .. it[1],"
            " Description = \"Level 4 cinema v3 chunk \" .. it[1], CreatorId = " + str(GROUP) + ", CreatorType = Enum.AssetCreatorType.Group})\n"
            "      if status == Enum.CreateAssetResult.Success then break end\n"
            "      task.wait(5 * attempt)\n"
            "    end\n"
            "    em:Destroy()\n"
            "    if status ~= Enum.CreateAssetResult.Success then error(tostring(status)) end\n"
            "    return assetId\n"
            "  end)\n"
            "  table.insert(out, it[1] .. \"=\" .. (ok and tostring(res) or (\"ERR:\" .. tostring(res))))\n"
            "end\nreturn table.concat(out, \"\\n\")\n")
    t, e = call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
    hashes = {cid: h for cid, _, h in batch}
    for line in t.splitlines():
        if "=" not in line:
            continue
        k, v = line.split("=", 1)
        if not k.strip().isdigit():
            continue
        cid = int(k)
        if v.startswith("ERR"):
            print("chunk", cid, v, flush=True)
            out.write(json.dumps({"id": cid, "error": v}) + "\n")
        else:
            out.write(json.dumps({"id": cid, "asset": int(v), "h": hashes.get(cid)}) + "\n")
            n += 1
    out.flush()
    if e:
        print("batch", bi, "ERROR", t[:500], flush=True)
    print("batch %d/%d done, uploaded %d" % (bi + 1, len(batches), n), flush=True)
c.close()
print("FINISHED uploaded", n, flush=True)
