"""Upload one validated Pool Slide KeyframeSequence through Roblox Open Cloud.

Saves the operation before polling. Never retries an ambiguous POST. No Studio writes.
"""
import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parents[1]
ANIM_DIR = ROOT / "assets" / "models" / "pool_slide" / "animations"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
ASSETS = "https://apis.roblox.com/assets/v1"
GROUP_ID = 1039373905


def api_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY not found in local secret file")


def save(receipt_path: Path, receipt: dict) -> None:
    receipt_path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("clip", choices=("walk", "run"))
    parser.add_argument("--upload", action="store_true")
    args = parser.parse_args()
    source = ANIM_DIR / f"pool_slide_{args.clip}_1p20_v1.rbxmx"
    receipt_path = ANIM_DIR / f"pool_slide_{args.clip}_1p20_v1_upload_receipt.json"
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("sha256") != sha:
            raise RuntimeError("Receipt hash differs from source; inspect before proceeding")
        if receipt.get("assetId"):
            print(f"Already created asset {receipt['assetId']} for {args.clip}")
            return
        if receipt.get("operationPath"):
            print(f"Resuming known operation {receipt['operationPath']}")
        else:
            raise RuntimeError("Receipt has no operation path; no blind retry")
    else:
        print(f"Candidate {args.clip}: {source.stat().st_size} bytes sha256 {sha}")
        if not args.upload:
            print("Dry run")
            return
        request = {
            "assetType": "Animation",
            "displayName": f"Pool Slide {args.clip.title()} 1.20x v1",
            "description": "BACKROOMS: STAY QUIET Level 2 candidate animation, 20-bone live rig retarget, in-place loop. Gameplay integration and corridor test pending.",
            "creationContext": {"creator": {"groupId": GROUP_ID}, "expectedPrice": 0},
        }
        session = requests.Session()
        session.headers["x-api-key"] = api_key()
        with source.open("rb") as animation:
            response = session.post(ASSETS + "/assets", files={
                "request": (None, json.dumps(request), "application/json"),
                "fileContent": (source.name, animation, "model/x-rbxm"),
            }, timeout=90)
        if not response.ok:
            print(f"Upload rejected: HTTP {response.status_code} {response.text[:800]}")
            raise SystemExit(1)
        operation = response.json()
        receipt = {
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha,
            "groupId": GROUP_ID,
            "expectedPrice": 0,
            "createdAtUtc": datetime.now(timezone.utc).isoformat(),
            "operationPath": operation.get("path"),
            "assetId": None,
            "status": "processing",
        }
        if not receipt["operationPath"]:
            raise RuntimeError(f"Accepted upload returned no operation path: {operation}")
        save(receipt_path, receipt)
    session = requests.Session()
    session.headers["x-api-key"] = api_key()
    for _ in range(60):
        response = session.get(ASSETS + "/" + receipt["operationPath"], timeout=30)
        response.raise_for_status()
        operation = response.json()
        if operation.get("done"):
            if operation.get("error"):
                receipt["status"] = "failed"
                receipt["error"] = operation["error"]
                save(receipt_path, receipt)
                raise RuntimeError(f"Roblox import failed: {operation['error']}")
            result = operation.get("response") or {}
            receipt["assetId"] = result.get("assetId")
            receipt["status"] = "created" if receipt["assetId"] else "unknown"
            receipt["result"] = {key: result.get(key) for key in ("assetType", "displayName", "revisionId", "moderationResult", "state")}
            save(receipt_path, receipt)
            print(f"Operation done: assetId={receipt['assetId']}, status={receipt['status']}")
            return
        time.sleep(2)
    raise TimeoutError(f"Import still pending; resume from {receipt_path}")


if __name__ == "__main__":
    main()
