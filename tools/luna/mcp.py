"""Call one Studio MCP tool and keep image results.

    python tools/luna/mcp.py TOOL '{json args}' [--code file.luau] [--img out.png]

Like studio.py, but for any tool; image blocks (screen_capture) are written to --img.
"""
import base64
import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402

tool, rest = sys.argv[1], sys.argv[2:]
args = json.loads(rest.pop(0)) if rest and not rest[0].startswith("--") else {}
if "--code" in rest:
    args["code"] = Path(rest[rest.index("--code") + 1]).read_text(encoding="utf-8")
img = rest[rest.index("--img") + 1] if "--img" in rest else None
client = StudioMcpClient(find_mcp_batch())
try:
    client.initialize()
    time.sleep(1)
    studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 25)
    args.setdefault("studio_id", studio.get("studio_id") or studio.get("id"))
    res = client._request("tools/call", {"name": tool, "arguments": args}).get("result", {})
    n = 0
    for block in res.get("content", []):
        if block.get("type") == "text":
            sys.stdout.buffer.write(block["text"].encode("utf-8", "replace") + b"\n")
        elif block.get("type") == "image" and img:
            path = Path(img) if n == 0 else Path(img).with_stem(f"{Path(img).stem}_{n}")
            path.write_bytes(base64.b64decode(block["data"]))
            print("IMAGE", path)
            n += 1
    if res.get("isError"):
        sys.exit(1)
finally:
    client.close()
