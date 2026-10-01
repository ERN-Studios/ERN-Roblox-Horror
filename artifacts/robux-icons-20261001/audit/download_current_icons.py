"""Read-only download of Roblox thumbnail references for the live purchase audit."""
import concurrent.futures
import hashlib
import json
import re
import urllib.parse
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent
inventory = json.loads((ROOT / "robux-purchase-inventory.json").read_text())
refs = {}

def ref(asset_id, key, surface):
    if asset_id:
        refs.setdefault(str(asset_id), []).append({"key": key, "surface": surface})

for row in inventory["entries"]:
    ref(row.get("iconId"), row["key"], "Skin portrait" if row["catalog"] == "Skins" else "In-game icon")
    ref(row.get("marketplace", {}).get("iconId"), row["key"], "Roblox purchase icon")

src = (ROOT / "live-sources/ServerScriptService.LobbyShopDisplay.ModuleScript.luau").read_text()
box = src.split("local SHOP_TEXTURES = {", 1)[1].split("-- ── palette", 1)[0]
for key, asset_id in re.findall(r'(\w+)\s*=\s*"rbxassetid://(\d+)"', box):
    if key in {r["key"] for r in inventory["entries"]}:
        ref(asset_id, key, "Lobby box faces")

url = "https://thumbnails.roblox.com/v1/assets?" + urllib.parse.urlencode({
    "assetIds": ",".join(refs), "size": "420x420", "format": "Png", "isCircular": "false"
})
req = urllib.request.Request(url, headers={"User-Agent": "RobuxIconAudit/1.0"})
with urllib.request.urlopen(req, timeout=30) as response:
    metadata = json.load(response)
(ROOT / "current-icons").mkdir(exist_ok=True)
(ROOT / "thumbnail-api-response.json").write_text(json.dumps({"url": url, "response": metadata}, indent=2))

def download(row):
    asset_id = str(row["targetId"])
    receipt = {"assetId": asset_id, "references": refs[asset_id], "state": row.get("state"), "url": row.get("imageUrl")}
    if row.get("state") != "Completed" or not row.get("imageUrl"):
        return receipt
    request = urllib.request.Request(row["imageUrl"], headers={"User-Agent": "RobuxIconAudit/1.0"})
    try:
        with urllib.request.urlopen(request, timeout=30) as response:
            data = response.read()
            receipt["contentType"] = response.headers.get("Content-Type")
        if not data.startswith(b"\x89PNG\r\n\x1a\n"):
            raise ValueError("Thumbnail response is not a PNG")
        key = refs[asset_id][0]["key"]
        destination = ROOT / "current-icons" / (key + "-" + asset_id + ".png")
        destination.write_bytes(data)
        receipt.update({"path": str(destination.relative_to(ROOT)), "bytes": len(data), "sha256": hashlib.sha256(data).hexdigest(), "dimensions": [int.from_bytes(data[16:20], "big"), int.from_bytes(data[20:24], "big")]})
    except Exception as error:
        receipt["downloadError"] = str(error)
    return receipt

with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
    receipts = list(pool.map(download, metadata["data"]))
(ROOT / "current-icon-download-receipt.json").write_text(json.dumps({"authority": "Fresh Studio icon references; public Roblox 420x420 thumbnails, not the full-resolution originals", "purchaseInventoryCapturedAt": inventory["capturedAt"], "icons": receipts}, indent=2))
print(json.dumps({"uniqueReferences": len(refs), "downloaded": sum("path" in r for r in receipts), "errors": [r for r in receipts if "downloadError" in r or r.get("state") != "Completed"]}))
