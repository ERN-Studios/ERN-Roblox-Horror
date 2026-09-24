"""Upload the reviewed Ascendant art as group-owned Roblox assets.

This only creates library assets. It does not insert them into Studio or
publish a place. Each operation is recorded before polling and is resumable.
"""

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
RECEIPT = ROOT / "upload-receipt.json"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
API = "https://apis.roblox.com/assets/v1"
GROUP_ID = 1039373905
ASSETS = {
    "ascendant-color-map.png": (
        "Image", "image/png", "Signal Architect Ascendant Color Map",
        "Color map for the developer-only hazmat suit in BACKROOMS: STAY QUIET.",
    ),
    "ascendant-standing-card.png": (
        "Image", "image/png", "Signal Architect Ascendant Portrait",
        "Transparent portrait for the developer-only hazmat suit.",
    ),
    "ascendant-signal-mote.png": (
        "Image", "image/png", "Signal Architect Ascendant Mote",
        "Small transparent cosmetic particle sprite for the developer-only suit.",
    ),
    "ascendant-halo-backpiece.glb": (
        "Model", "model/gltf-binary", "Signal Architect Ascendant Halo",
        "Single mesh cosmetic halo backpiece for the developer-only hazmat suit.",
    ),
}


def key():
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY missing from local secret file")


def save(receipt):
    RECEIPT.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def get_metadata(session, asset_id):
    response = session.get(f"{API}/assets/{asset_id}", timeout=30)
    response.raise_for_status()
    return response.json()


def record_metadata(item, metadata):
    creator = (metadata.get("creationContext") or {}).get("creator") or {}
    if str(creator.get("groupId")) != str(GROUP_ID):
        item["status"] = "owner-unverified"
        raise RuntimeError(f"Group ownership unverified for asset {item['assetId']}")
    item["assetType"] = metadata.get("assetType")
    item["moderationState"] = (metadata.get("moderationResult") or {}).get("moderationState")
    item["status"] = "approved" if item["moderationState"] == "Approved" else "created"
    item["verifiedAtUtc"] = datetime.now(timezone.utc).isoformat()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload", action="store_true", help="submit any missing assets")
    parser.add_argument("--verify", action="store_true", help="refresh asset metadata")
    args = parser.parse_args()
    receipt = json.loads(RECEIPT.read_text(encoding="utf-8")) if RECEIPT.exists() else {}
    session = requests.Session()
    session.headers["x-api-key"] = key()
    for filename, (asset_type, mime_type, display, description) in ASSETS.items():
        source = ROOT / filename
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        item = receipt.get(filename)
        if item:
            if item["sha256"] != digest or item["groupId"] != GROUP_ID:
                raise RuntimeError(f"Receipt belongs to different content: {filename}")
            if item.get("assetId"):
                if args.verify:
                    try:
                        record_metadata(item, get_metadata(session, item["assetId"]))
                    finally:
                        save(receipt)
                print(f"{filename}: asset {item['assetId']} ({item.get('moderationState')})")
                continue
            if not item.get("operationPath"):
                raise RuntimeError(f"Ambiguous existing receipt for {filename}")
        else:
            print(f"{filename}: {source.stat().st_size} bytes, sha256 {digest}")
            if not args.upload:
                continue
            request = {
                "assetType": asset_type,
                "displayName": display,
                "description": description,
                "creationContext": {
                    "creator": {"groupId": GROUP_ID}, "expectedPrice": 0,
                },
            }
            with source.open("rb") as data:
                response = session.post(
                    f"{API}/assets",
                    files={
                        "request": (None, json.dumps(request), "application/json"),
                        "fileContent": (filename, data, mime_type),
                    },
                    timeout=90,
                )
            if not response.ok:
                raise RuntimeError(f"Roblox rejected {filename}: HTTP {response.status_code}")
            path = response.json().get("path")
            if not path:
                raise RuntimeError(f"No operation path returned for {filename}; inspect before retry")
            item = {
                "sha256": digest, "groupId": GROUP_ID,
                "createdAtUtc": datetime.now(timezone.utc).isoformat(),
                "operationPath": path, "assetId": None, "status": "processing",
            }
            receipt[filename] = item
            save(receipt)
        for _ in range(60):
            response = session.get(f"{API}/{item['operationPath']}", timeout=30)
            response.raise_for_status()
            operation = response.json()
            if operation.get("done"):
                if operation.get("error"):
                    item["status"] = "failed"
                    item["error"] = operation["error"]
                    save(receipt)
                    raise RuntimeError(f"Roblox import failed for {filename}")
                asset_id = (operation.get("response") or {}).get("assetId")
                if not asset_id:
                    item["status"] = "unknown"
                    save(receipt)
                    raise RuntimeError(f"Operation finished without asset ID for {filename}")
                item["assetId"] = asset_id
                try:
                    record_metadata(item, get_metadata(session, asset_id))
                finally:
                    save(receipt)
                print(f"{filename}: asset {asset_id} ({item['moderationState']})")
                break
            time.sleep(2)
        else:
            raise TimeoutError(f"Operation still processing for {filename}; rerun to resume")


if __name__ == "__main__":
    main()
