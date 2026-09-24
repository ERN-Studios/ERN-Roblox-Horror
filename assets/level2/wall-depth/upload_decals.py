"""Upload reviewed Level 2 transparent decals to the game's Roblox group.

The local receipt is resumable and prevents duplicate uploads. This does not
insert decals into Studio or publish the place.
"""

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
RECEIPT_FILE = ROOT / "decal-upload-receipt.json"
API = "https://apis.roblox.com/assets/v1"
GROUP_ID = 1039373905
IMAGES = {
    "decal-maintenance-v1.png": ("Level 2 Maintenance Wall Decal", "Transparent environmental wall dressing for BACKROOMS: STAY QUIET Level 2."),
    "decal-visitor-traces-v1.png": ("Level 2 Visitor Traces Wall Decal", "Transparent environmental wall dressing for BACKROOMS: STAY QUIET Level 2."),
}


def key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY missing from local secret file")


def save(receipt: dict) -> None:
    RECEIPT_FILE.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload", action="store_true")
    parser.add_argument("--verify", action="store_true")
    args = parser.parse_args()
    receipt = json.loads(RECEIPT_FILE.read_text(encoding="utf-8")) if RECEIPT_FILE.exists() else {}
    session = requests.Session()
    session.headers["x-api-key"] = key()

    for filename, (name, description) in IMAGES.items():
        digest = hashlib.sha256((ROOT / filename).read_bytes()).hexdigest()
        item = receipt.get(filename)
        if item:
            if item["sha256"] != digest or item["groupId"] != GROUP_ID:
                raise RuntimeError(f"Receipt does not match {filename}")
            if item.get("assetId"):
                if args.verify:
                    response = session.get(f"{API}/assets/{item['assetId']}", timeout=30)
                    response.raise_for_status()
                    metadata = response.json()
                    creator = (metadata.get("creationContext") or {}).get("creator") or {}
                    if str(creator.get("groupId")) != str(GROUP_ID):
                        raise RuntimeError(f"Group ownership not verified: {filename}")
                    item["moderationState"] = (metadata.get("moderationResult") or {}).get("moderationState")
                    item["verifiedAtUtc"] = datetime.now(timezone.utc).isoformat()
                    save(receipt)
                print(f"{filename}: existing {item['assetId']}, {item.get('moderationState')}")
                continue
            if not item.get("operationPath"):
                raise RuntimeError(f"Ambiguous prior upload: {filename}")
        else:
            if not args.upload:
                print(f"{filename}: ready, {digest}")
                continue
            request = {
                "assetType": "Image",
                "displayName": name,
                "description": description,
                "creationContext": {"creator": {"groupId": GROUP_ID}, "expectedPrice": 0},
            }
            with (ROOT / filename).open("rb") as data:
                response = session.post(
                    f"{API}/assets",
                    files={
                        "request": (None, json.dumps(request), "application/json"),
                        "fileContent": (filename, data, "image/png"),
                    },
                    timeout=90,
                )
            if not response.ok:
                raise RuntimeError(f"Roblox rejected {filename}: HTTP {response.status_code}")
            path = response.json().get("path")
            if not path:
                raise RuntimeError(f"No operation path for {filename}; inspect before retrying")
            item = {
                "sha256": digest,
                "groupId": GROUP_ID,
                "createdAtUtc": datetime.now(timezone.utc).isoformat(),
                "operationPath": path,
                "assetId": None,
                "status": "processing",
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
                    raise RuntimeError(f"Import failed: {filename}")
                result = operation.get("response") or {}
                item["assetId"] = result.get("assetId")
                item["moderationState"] = (result.get("moderationResult") or {}).get("moderationState")
                details = session.get(f"{API}/assets/{item['assetId']}", timeout=30)
                details.raise_for_status()
                metadata = details.json()
                creator = (metadata.get("creationContext") or {}).get("creator") or {}
                if str(creator.get("groupId")) != str(GROUP_ID):
                    item["status"] = "owner-unverified"
                    save(receipt)
                    raise RuntimeError(f"Group ownership not verified: {filename}")
                item["moderationState"] = (metadata.get("moderationResult") or {}).get("moderationState") or item["moderationState"]
                item["status"] = "created"
                save(receipt)
                print(f"{filename}: asset {item['assetId']}, {item['moderationState']}")
                break
            time.sleep(2)
        else:
            raise TimeoutError(f"Import still processing: {filename}; resume from receipt")


if __name__ == "__main__":
    main()
