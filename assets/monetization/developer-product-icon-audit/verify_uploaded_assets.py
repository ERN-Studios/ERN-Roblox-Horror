"""Read back the three icon assets' Roblox moderation and availability state."""

import json
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"


def main() -> None:
    key = next(
        line.partition("=")[2].strip().strip('"').strip("'")
        for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines()
        if line.startswith("ROBLOX_API_KEY=")
    )
    session = requests.Session()
    session.headers["x-api-key"] = key
    receipt = json.loads((ROOT / "apply-three-receipt.json").read_text(encoding="utf-8"))
    rows = []
    for product in receipt["products"]:
        asset_id = product["afterIconImageAssetId"]
        response = session.get(f"https://apis.roblox.com/assets/v1/assets/{asset_id}", timeout=30)
        response.raise_for_status()
        asset = response.json()
        rows.append({
            "productId": product["productId"],
            "assetId": asset["assetId"],
            "assetType": asset["assetType"],
            "state": asset["state"],
            "moderationState": asset.get("moderationResult", {}).get("moderationState"),
        })
    result = {"verifiedAtUtc": datetime.now(timezone.utc).isoformat(), "assets": rows}
    (ROOT / "uploaded-assets-readback.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
    print([(row["assetId"], row["state"], row["moderationState"]) for row in rows])


if __name__ == "__main__":
    main()
