"""Upload one versioned Pool Slide animation candidate through Open Cloud.

An accepted POST is recorded before polling. Never retry an ambiguous create.
The current Studio rig and its AnimationIds are untouched.
"""

import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parents[1]
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


def save(path: Path, receipt: dict) -> None:
    path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("source", type=Path)
    parser.add_argument("--display-name", required=True)
    parser.add_argument("--upload", action="store_true")
    args = parser.parse_args()
    source = args.source.resolve(strict=True)
    if source.suffix.lower() != ".rbxmx" or ROOT not in source.parents:
        raise ValueError("Source must be an RBXMX inside this repository")
    receipt_path = source.with_name(source.stem + "_upload_receipt.json")
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    session = requests.Session()
    session.headers["x-api-key"] = api_key()

    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("sha256") != sha:
            raise RuntimeError("Receipt hash differs from source; inspect before proceeding")
        if receipt.get("assetId"):
            print(f"Already created asset {receipt['assetId']}")
            return
        if not receipt.get("operationPath"):
            raise RuntimeError("Receipt has no operation path; no blind retry")
        print(f"Resuming known operation {receipt['operationPath']}")
    else:
        print(f"Candidate: {source.relative_to(ROOT)} ({source.stat().st_size} bytes), SHA-256 {sha}")
        if not args.upload:
            print("Dry run")
            return
        request = {
            "assetType": "Animation",
            "displayName": args.display_name,
            "description": "BACKROOMS: STAY QUIET Pool Slide isolated gait A/B candidate; not installed in the game.",
            "creationContext": {"creator": {"groupId": GROUP_ID}, "expectedPrice": 0},
        }
        receipt = {
            "source": str(source.relative_to(ROOT)).replace("\\", "/"),
            "sha256": sha,
            "groupId": GROUP_ID,
            "expectedPrice": 0,
            "createdAtUtc": datetime.now(timezone.utc).isoformat(),
            "operationPath": None,
            "assetId": None,
            "status": "sending_unresolved_if_interrupted",
        }
        save(receipt_path, receipt)
        with source.open("rb") as animation:
            response = session.post(ASSETS + "/assets", files={
                "request": (None, json.dumps(request), "application/json"),
                "fileContent": (source.name, animation, "model/x-rbxm"),
            }, timeout=90)
        if not response.ok:
            receipt["status"] = "rejected"
            receipt["httpStatus"] = response.status_code
            save(receipt_path, receipt)
            print(f"Upload rejected: HTTP {response.status_code} {response.text[:800]}")
            raise SystemExit(1)
        operation = response.json()
        receipt["operationPath"] = operation.get("path")
        receipt["status"] = "processing" if receipt["operationPath"] else "accepted_without_operation_path"
        save(receipt_path, receipt)
        if not receipt["operationPath"]:
            raise RuntimeError(f"Accepted upload returned no operation path: {operation}")

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
            receipt["result"] = {key: result.get(key) for key in (
                "assetType", "displayName", "revisionId", "moderationResult", "state"
            )}
            save(receipt_path, receipt)
            print(f"Operation done: assetId={receipt['assetId']}, status={receipt['status']}")
            return
        time.sleep(2)
    raise TimeoutError(f"Import still pending; resume from {receipt_path}")


if __name__ == "__main__":
    main()
