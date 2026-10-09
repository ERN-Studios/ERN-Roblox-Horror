"""Upload one Luna asset to the ERN Roblox Studios group through Open Cloud.

    python tools/luna/upload_asset.py <file.glb|file.rbxmx> --display-name "Luna ..." [--upload]

.glb -> assetType Model, .rbxmx -> assetType Animation. Without --upload it is a dry run.
A receipt (tools/luna/receipts/<stem>.json, keyed by the file's SHA-256) is written BEFORE the POST
and an ambiguous create is never retried blindly: rerunning resumes the recorded operation.
Adapted from the Pool Slide uploader (worktree wall-depth-v2-20260924, tools/pool_slide_upload_candidate.py).
"""
import argparse
import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests

HERE = Path(__file__).resolve().parent
RECEIPTS = HERE / "receipts"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
ASSETS = "https://apis.roblox.com/assets/v1"
GROUP_ID = 1039373905
KINDS = {".glb": ("Model", "model/gltf-binary"), ".rbxmx": ("Animation", "model/x-rbxm")}


def api_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            value = line.partition("=")[2].strip().strip('"').strip("'")
            if value:
                return value
    raise RuntimeError("ROBLOX_API_KEY not found in local secret file")


def save(path: Path, receipt: dict) -> None:
    path.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8")


def upload(source: Path, display_name: str, really: bool, description: str = "") -> dict:
    source = source.resolve(strict=True)
    asset_type, mime = KINDS[source.suffix.lower()]
    RECEIPTS.mkdir(exist_ok=True)
    receipt_path = RECEIPTS / (source.stem + ".json")
    sha = hashlib.sha256(source.read_bytes()).hexdigest()
    session = requests.Session()
    session.headers["x-api-key"] = api_key()
    if receipt_path.exists():
        receipt = json.loads(receipt_path.read_text(encoding="utf-8"))
        if receipt.get("sha256") != sha:
            raise RuntimeError(f"{receipt_path.name}: receipt is for a different file; bump the file name for a new version")
        if receipt.get("assetId"):
            print(f"{source.name}: already asset {receipt['assetId']}")
            return receipt
        if not receipt.get("operationPath"):
            raise RuntimeError(f"{receipt_path.name}: no operation path recorded; inspect manually, no blind retry")
        print(f"{source.name}: resuming {receipt['operationPath']}")
    else:
        print(f"{source.name}: {asset_type}, {source.stat().st_size} bytes, sha256 {sha}")
        if not really:
            print("dry run (add --upload)")
            return {}
        request = {
            "assetType": asset_type,
            "displayName": display_name,
            "description": description or "BACKROOMS: STAY QUIET lobby tribute: Luna.",
            "creationContext": {"creator": {"groupId": GROUP_ID}, "expectedPrice": 0},
        }
        receipt = {"source": source.name, "sha256": sha, "assetType": asset_type, "displayName": display_name,
                   "groupId": GROUP_ID, "expectedPrice": 0,
                   "createdAtUtc": datetime.now(timezone.utc).isoformat(),
                   "operationPath": None, "assetId": None, "status": "sending_unresolved_if_interrupted"}
        save(receipt_path, receipt)
        with source.open("rb") as fh:
            response = session.post(ASSETS + "/assets", files={
                "request": (None, json.dumps(request), "application/json"),
                "fileContent": (source.name, fh, mime),
            }, timeout=120)
        if not response.ok:
            receipt.update(status="rejected", httpStatus=response.status_code, body=response.text[:800])
            save(receipt_path, receipt)
            raise SystemExit(f"{source.name}: rejected HTTP {response.status_code} {response.text[:800]}")
        receipt["operationPath"] = response.json().get("path")
        receipt["status"] = "processing"
        save(receipt_path, receipt)
    for _ in range(90):
        response = session.get(ASSETS + "/" + receipt["operationPath"], timeout=30)
        response.raise_for_status()
        op = response.json()
        if op.get("done"):
            if op.get("error"):
                receipt.update(status="failed", error=op["error"])
                save(receipt_path, receipt)
                raise RuntimeError(f"{source.name}: import failed {op['error']}")
            result = op.get("response") or {}
            receipt["assetId"] = result.get("assetId")
            receipt["status"] = "created" if receipt["assetId"] else "unknown"
            receipt["result"] = {k: result.get(k) for k in ("assetType", "displayName", "revisionId", "moderationResult", "state")}
            save(receipt_path, receipt)
            print(f"{source.name}: assetId={receipt['assetId']} {receipt['result']}")
            return receipt
        time.sleep(2)
    raise TimeoutError(f"{source.name}: still pending; rerun to resume")


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("source", type=Path)
    p.add_argument("--display-name", required=True)
    p.add_argument("--description", default="")
    p.add_argument("--upload", action="store_true")
    a = p.parse_args()
    upload(a.source, a.display_name, a.upload, a.description)
