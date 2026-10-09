"""Upload only the nine Level 1 PBR maps; retain a resumable asset receipt."""
import functools
import argparse
import hashlib
import http.server
import json
from pathlib import Path
import sys
import threading

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio

SOURCE = ROOT / "assets/level1/blender/textures"
RECEIPT = SOURCE / "published.json"


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--assets", type=Path, default=SOURCE.parent)
    args = parser.parse_args()
    source = args.assets.resolve() / "textures"
    assert source.is_relative_to(ROOT / "assets/level1"), "Only Level 1 texture directories are supported"
    receipt_path = source / "published.json"
    manifest = json.loads((source.parent / "export/manifest.json").read_text(encoding="utf-8"))
    names = sorted({name for material in manifest["materials"].values() for name in material["maps"].values()})
    hashes = {name: hashlib.sha256((source / name).read_bytes()).hexdigest() for name in names}
    receipt = json.loads(receipt_path.read_text()) if receipt_path.exists() else {}
    pending = [name for name in names if receipt.get(name, {}).get("sha256") != hashes[name]]
    if not pending:
        print("All PBR maps already uploaded at these hashes.")
        return
    server = http.server.ThreadingHTTPServer(("127.0.0.1", 0),
        functools.partial(http.server.SimpleHTTPRequestHandler, directory=str(source)))
    thread = threading.Thread(target=server.serve_forever, daemon=True)
    thread.start()
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        studio = select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        urls = {name: f"http://127.0.0.1:{server.server_port}/{name}" for name in pending}
        uploaded = json.loads(client.call("upload_image", {
            "studio_id": studio["id"], "imagePaths": list(urls.values())}))
        for name, url in urls.items():
            asset = uploaded.get(url)
            if not isinstance(asset, str) or not asset.startswith("rbxassetid://"):
                raise RuntimeError(f"Missing asset receipt for {name}: {uploaded}")
            receipt[name] = {"assetId": asset, "sha256": hashes[name], "file": name}
            receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")
            print(name, asset, flush=True)
    finally:
        client.close()
        server.shutdown()
        server.server_close()
        thread.join(timeout=2)


if __name__ == "__main__":
    main()
