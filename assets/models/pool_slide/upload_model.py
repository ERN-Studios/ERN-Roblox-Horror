"""Upload the validated Pool Slide GLB to the Roblox group using Open Cloud.

The operation is recorded immediately and never blindly retried. Upload fee is
explicitly capped at zero Robux. This does not insert the model into Studio.
"""

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

ROOT = Path(__file__).resolve().parent
MODEL = ROOT / "pool_slide_scaled_walk_run_v1.glb"
RECEIPT = ROOT / "pool_slide_upload_receipt.json"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
ASSETS = "https://apis.roblox.com/assets/v1"


def api_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY not found in local secret file")


def save(receipt: dict) -> None:
    RECEIPT.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--upload", action="store_true", help="perform one group-owned upload")
    args = parser.parse_args()
    sha = hashlib.sha256(MODEL.read_bytes()).hexdigest()
    if RECEIPT.exists():
        receipt = json.loads(RECEIPT.read_text(encoding="utf-8"))
        if receipt.get("sha256") != sha:
            raise RuntimeError("Receipt refers to a different GLB; do not reuse or overwrite it")
        if receipt.get("assetId"):
            print(f"Already uploaded candidate asset {receipt['assetId']} (sha256 {sha})")
            return
        if receipt.get("operationPath"):
            print(f"Resuming known operation {receipt['operationPath']}")
        else:
            raise RuntimeError("Existing receipt has no operation or asset ID; inspect manually")
    else:
        print(f"Candidate: {MODEL.name}, {MODEL.stat().st_size} bytes, sha256 {sha}")
        if not args.upload:
            print("Dry run; add --upload to create one off-game model asset")
            return
        request = {
            "assetType": "Model",
            "displayName": "Pool Slide Enlarged Walk Run v1",
            "description": "BACKROOMS: STAY QUIET Level 2 candidate. Original 20-bone rig, 1.20x scale, polished Walk/Run. Requires live corridor/navigation and sound-origin QA before use.",
            "creationContext": {"creator": {"groupId": 1039373905}, "expectedPrice": 0},
        }
        session = requests.Session()
        session.headers["x-api-key"] = api_key()
        with MODEL.open("rb") as glb:
            response = session.post(
                ASSETS + "/assets",
                files={
                    "request": (None, json.dumps(request), "application/json"),
                    "fileContent": (MODEL.name, glb, "model/gltf-binary"),
                },
                timeout=90,
            )
        if not response.ok:
            print(f"Upload rejected: HTTP {response.status_code} {response.text[:800]}")
            raise SystemExit(1)
        operation = response.json()
        receipt = {
            "source": str(MODEL.relative_to(ROOT.parent.parent.parent)),
            "sha256": sha,
            "groupId": 1039373905,
            "createdAtUtc": datetime.now(timezone.utc).isoformat(),
            "operationPath": operation.get("path"),
            "assetId": None,
            "status": "processing",
        }
        if not receipt["operationPath"]:
            raise RuntimeError(f"Upload returned no operation path: {operation}")
        save(receipt)
    session = requests.Session()
    session.headers["x-api-key"] = api_key()
    path = receipt["operationPath"]
    for _ in range(60):
        response = session.get(ASSETS + "/" + path, timeout=30)
        response.raise_for_status()
        operation = response.json()
        if operation.get("done"):
            if operation.get("error"):
                receipt["status"] = "failed"
                receipt["error"] = operation["error"]
                save(receipt)
                raise RuntimeError(f"Roblox import failed: {operation['error']}")
            result = operation.get("response") or {}
            receipt["assetId"] = result.get("assetId")
            receipt["status"] = "created" if receipt["assetId"] else "unknown"
            receipt["result"] = {
                key: result.get(key)
                for key in ("assetType", "displayName", "revisionId", "moderationResult", "state")
            }
            save(receipt)
            print(f"Operation done: assetId={receipt['assetId']}, status={receipt['status']}")
            return
        time.sleep(2)
    raise TimeoutError(f"Import still pending; resume from {RECEIPT}")


if __name__ == "__main__":
    main()
