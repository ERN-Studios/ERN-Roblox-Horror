"""Upload the coordinated lobby concrete textures through Roblox Studio MCP."""

from __future__ import annotations

import functools
import http.server
import json
import sys
import threading
import time
from pathlib import Path
from urllib.parse import quote

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


ROOT = Path(__file__).resolve().parents[1]
SOURCE = ROOT / "assets" / "textures" / "lobby_concrete"
FILES = {
    "wall_fine_a": "concrete_wall_fine_a.png",
    "wall_fine_b": "concrete_wall_fine_b.png",
    "floor_dense": "concrete_floor_dense.png",
    "curb_light": "concrete_curb_light.png",
}


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, _format: str, *_args: object) -> None:
        return


def main() -> int:
    missing = [filename for filename in FILES.values() if not (SOURCE / filename).is_file()]
    if missing:
        raise FileNotFoundError(f"Missing lobby concrete textures: {missing}")

    handler = functools.partial(QuietHandler, directory=str(SOURCE))
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    port = server.server_address[1]
    urls = {
        role: f"http://127.0.0.1:{port}/{quote(filename)}"
        for role, filename in FILES.items()
    }

    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        raw = client.call("upload_image", {"imagePaths": list(urls.values())})
        uploaded = json.loads(raw)
    finally:
        client.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)

    results: dict[str, dict[str, str]] = {}
    for role, url in urls.items():
        asset_id = uploaded.get(url)
        if not isinstance(asset_id, str) or not asset_id.startswith("rbxassetid://"):
            raise RuntimeError(f"No Roblox asset id returned for {role}: {raw}")
        results[role] = {"assetId": asset_id, "file": FILES[role]}
        print(json.dumps({"role": role, "assetId": asset_id}, ensure_ascii=False))

    (SOURCE / "published-lobby-concrete.json").write_text(
        json.dumps(results, ensure_ascii=False, indent=2) + "\n", encoding="utf-8"
    )
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
