# Sandbox-friendly replacement for "serve.py + place.luau": stage the placement packet and the asset map as
# StringValues in ServerStorage.L4PlaceStaging, then run place_phases.luau (templates, placements, rest), whose
# helpers come verbatim from tools/level4_blender/place.luau.
#   python place_driver.py [export_dir] [--phase templates|placements|rest] [--stage-only]
import json, os, sys, time

sys.path.insert(0, r"G:\Roblox\MongoTV\tools")
import sync_from_studio as s

HERE = os.path.dirname(os.path.abspath(__file__))
TOOLS = r"G:\Roblox\MongoTV\tools\level4_blender"
args = sys.argv[1:]
EXPORT = args[0] if args and not args[0].startswith("--") else r"G:\Roblox\_local\l4blender\export"
PIECE = 190_000

packet = open(os.path.join(EXPORT, "chunks", "c99999.b64"), encoding="utf-8").read()
json.loads(packet)                                         # it is JSON text, despite the name
assets = {}
for line in open(os.path.join(TOOLS, "results.jsonl")):
    r = json.loads(line)
    if r.get("asset"):
        assets[str(r["id"])] = r["asset"]
need = {str(c["id"]) for c in json.load(open(os.path.join(EXPORT, "manifest.json")))["chunks"]}
missing = sorted(need - set(assets), key=int)
assert not missing, "chunks without an uploaded asset: %s" % missing[:20]
assets_txt = json.dumps({k: assets[k] for k in need})

src = open(os.path.join(TOOLS, "place.luau"), encoding="utf-8").read()
helpers = src[src.index("local AS = "):src.index("local function fetch()")] + \
    src[src.index("local function vec(t)"):src.index("local function run()")]
push = open(os.path.join(TOOLS, "PushDoors.server.lua"), encoding="utf-8").read()
assert "]==]" not in push
helpers = helpers.replace("__PUSH_DOOR_SOURCE__", "[==[\n" + push + "\n]==]")
phases = open(os.path.join(HERE, "place_phases.luau"), encoding="utf-8").read()

c = s.StudioMcpClient(s.find_mcp_batch())
c.initialize()


def call(tool, a, timeout=3600):
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


def luau(code):
    t, e = call("execute_luau", {"studio_id": sid, "datamodel_type": "Edit", "code": code})
    return ("ERROR: " if e else "") + t


def stage():
    print(luau('local SS = game:GetService("ServerStorage")\nlocal f = SS:FindFirstChild("L4PlaceStaging")\n'
               'if f then f:Destroy() end\nf = Instance.new("Folder")\nf.Name = "L4PlaceStaging"\nf.Parent = SS\nreturn "staging reset"'))
    pieces = [("P%03d" % (i // PIECE), packet[i:i + PIECE]) for i in range(0, len(packet), PIECE)]
    pieces += [("A%03d" % (i // PIECE), assets_txt[i:i + PIECE]) for i in range(0, len(assets_txt), PIECE)]
    for k in range(0, len(pieces), 4):
        body = ['local f = game:GetService("ServerStorage"):WaitForChild("L4PlaceStaging")']
        for name, text in pieces[k:k + 4]:
            eq = "=" * 8
            assert ("]" + eq + "]") not in text
            body.append('do local v = Instance.new("StringValue"); v.Name = "%s"; v.Value = [%s[%s]%s]; v.Parent = f end'
                        % (name, eq, text, eq))
        body.append('return "staged " .. #f:GetChildren()')
        print(luau("\n".join(body)), flush=True)


if "--phase" in args:
    todo = [args[args.index("--phase") + 1]]
else:
    stage()
    todo = [] if "--stage-only" in args else ["templates", "placements", "rest"]
for ph in todo:
    t0 = time.time()
    out = luau(helpers + "\n" + phases.replace("__PHASE__", ph))
    print("[%s %.0fs] %s" % (ph, time.time() - t0, out[:2000]), flush=True)
    if out.startswith("ERROR"):
        break
c.close()
