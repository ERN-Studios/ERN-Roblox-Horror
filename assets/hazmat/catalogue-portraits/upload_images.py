"""Upload reviewed standing hazmat shop cards to the Roblox group.

The receipt makes each upload resumable and prevents an accidental duplicate.
This does not insert either image into Studio or publish a place version.
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
RECEIPT_FILE = ROOT / "upload-receipt.json"
ASSETS_API = "https://apis.roblox.com/assets/v1"
GROUP_ID = 1039373905
IMAGES = {
    "baseline-yellow-standing-card-v1.png": ("Baseline Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "pool-service-standing-card-v1.png": ("Pool Service Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "suburb-survey-standing-card-v1.png": ("Suburb Survey Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "blacksite-director-standing-card-v1.png": ("Blacksite Director Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "static-wraith-standing-card-v1.png": ("Static Wraith Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "false-sun-standing-card-v1.png": ("False Sun Hazmat Standing Shop Card", "Standing cosmetic shop portrait for BACKROOMS: STAY QUIET."),
    "signal-architect-standing-card-v1.png": ("Signal Architect Hazmat Standing Shop Card", "Standing developer cosmetic shop portrait for BACKROOMS: STAY QUIET."),
}


def api_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY not found in the local secret file")


def save(receipt: dict) -> None:
    RECEIPT_FILE.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload", action="store_true", help="submit missing images")
    parser.add_argument("--verify", action="store_true", help="refresh existing moderation status")
    args = parser.parse_args()
    receipt = json.loads(RECEIPT_FILE.read_text(encoding="utf-8")) if RECEIPT_FILE.exists() else {}
    session = requests.Session()
    session.headers["x-api-key"] = api_key()

    for filename, (display_name, description) in IMAGES.items():
        source = ROOT / filename
        digest = hashlib.sha256(source.read_bytes()).hexdigest()
        item = receipt.get(filename)
        if item:
            if item["sha256"] != digest or item["groupId"] != GROUP_ID:
                raise RuntimeError(f"Existing receipt refers to different content: {filename}")
            if item.get("assetId"):
                if args.verify:
                    response = session.get(ASSETS_API + "/assets/" + str(item["assetId"]), timeout=30)
                    response.raise_for_status()
                    metadata = response.json()
                    creator = (metadata.get("creationContext") or {}).get("creator") or {}
                    if str(creator.get("groupId")) != str(GROUP_ID):
                        raise RuntimeError(f"Group ownership not verified for {filename}")
                    item["moderationState"] = (metadata.get("moderationResult") or {}).get("moderationState")
                    item["status"] = "approved" if item["moderationState"] == "Approved" else "created"
                    item["verifiedAtUtc"] = datetime.now(timezone.utc).isoformat()
                    save(receipt)
                print(f"{filename}: existing asset {item['assetId']}, moderation {item.get('moderationState')}")
                continue
            if not item.get("operationPath"):
                raise RuntimeError(f"Ambiguous prior upload of {filename}; inspect before retrying")
        else:
            print(f"{filename}: {source.stat().st_size} bytes, sha256 {digest}")
            if not args.upload:
                continue
            request = {
                "assetType": "Image",
                "displayName": display_name,
                "description": description,
                "creationContext": {"creator": {"groupId": GROUP_ID}, "expectedPrice": 0},
            }
            with source.open("rb") as data:
                response = session.post(
                    ASSETS_API + "/assets",
                    files={
                        "request": (None, json.dumps(request), "application/json"),
                        "fileContent": (filename, data, "image/png"),
                    },
                    timeout=90,
                )
            if not response.ok:
                raise RuntimeError(f"Roblox rejected {filename}: HTTP {response.status_code}")
            operation = response.json()
            path = operation.get("path")
            if not path:
                raise RuntimeError(f"Roblox returned no operation path for {filename}; inspect before retrying")
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
            response = session.get(ASSETS_API + "/" + item["operationPath"], timeout=30)
            response.raise_for_status()
            operation = response.json()
            if operation.get("done"):
                if operation.get("error"):
                    item["status"] = "failed"
                    item["error"] = operation["error"]
                    save(receipt)
                    raise RuntimeError(f"Roblox import failed for {filename}")
                result = operation.get("response") or {}
                creator = (result.get("creationContext") or {}).get("creator") or {}
                item["assetId"] = result.get("assetId")
                item["assetType"] = result.get("assetType")
                item["moderationState"] = (result.get("moderationResult") or {}).get("moderationState")
                if not creator.get("groupId") and item["assetId"]:
                    details = session.get(ASSETS_API + "/assets/" + str(item["assetId"]), timeout=30)
                    if details.ok:
                        metadata = details.json()
                        creator = (metadata.get("creationContext") or {}).get("creator") or {}
                        item["moderationState"] = (metadata.get("moderationResult") or {}).get("moderationState") or item["moderationState"]
                if str(creator.get("groupId")) != str(GROUP_ID):
                    item["status"] = "owner-unverified"
                    save(receipt)
                    raise RuntimeError(f"Group ownership not verified for {filename}")
                item["status"] = "created" if item["assetId"] else "unknown"
                save(receipt)
                print(f"{filename}: asset {item['assetId']}, moderation {item['moderationState']}")
                break
            time.sleep(2)
        else:
            raise TimeoutError(f"Roblox import still processing for {filename}; resume from receipt")


if __name__ == "__main__":
    main()
