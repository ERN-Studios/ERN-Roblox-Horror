"""Update ONLY the three gray-cube Developer Product images, then verify fields.

Requires explicit visual review of the proposed 128px circle sheet first. The
Roblox API key stays in the local secret file. Re-running after an uncertain
response will stop rather than issue a second upload.
"""

from __future__ import annotations

import hashlib
import json
import time
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
UNIVERSE_ID = 10559217407
BASE = f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE_ID}/developer-products"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
OLD_ICON = 88963008124478
PRODUCTS = [
    (3713829859, "Zyntra Expedition Pack", "expedition-pack-round-512.png"),
    (3713115025, "Donate — 5,000 Robux", "donation-5k-round-512.png"),
    (3713115125, "Donate — 10,000 Robux", "donation-10k-round-512.png"),
]
INVARIANT_FIELDS = (
    "productId", "name", "description", "universeId", "isForSale",
    "priceInformation", "isImmutable", "createdTimestamp",
    "isManagedPricingEnabled",
)


def key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            return line.partition("=")[2].strip().strip('"').strip("'")
    raise RuntimeError("ROBLOX_API_KEY unavailable")


def get(session: requests.Session, product_id: int) -> dict:
    response = session.get(f"{BASE}/{product_id}/creator", timeout=30)
    response.raise_for_status()
    return response.json()


def compact(row: dict) -> dict:
    return {field: row.get(field) for field in (*INVARIANT_FIELDS, "iconImageAssetId", "updatedTimestamp")}


def save(path: Path, value: dict) -> None:
    path.write_text(json.dumps(value, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")


def main() -> None:
    session = requests.Session()
    session.headers["x-api-key"] = key()
    before_path = ROOT / "before-three-state.json"
    if before_path.exists():
        before = json.loads(before_path.read_text(encoding="utf-8"))
    else:
        before = {
            "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
            "universeId": UNIVERSE_ID,
            "products": {str(pid): compact(get(session, pid)) for pid, _, _ in PRODUCTS},
        }
        save(before_path, before)

    receipt_path = ROOT / "apply-three-receipt.json"
    receipt = json.loads(receipt_path.read_text(encoding="utf-8")) if receipt_path.exists() else {
        "appliedAtUtc": datetime.now(timezone.utc).isoformat(),
        "universeId": UNIVERSE_ID,
        "products": [],
    }
    finished = {int(row["productId"]) for row in receipt["products"]}

    for pid, expected_name, filename in PRODUCTS:
        old = before["products"][str(pid)]
        if old["name"] != expected_name or old["iconImageAssetId"] != OLD_ICON:
            raise RuntimeError(f"{pid}: baseline name or icon did not match expected gray cube")
        current = compact(get(session, pid))
        for field in INVARIANT_FIELDS:
            if current[field] != old[field]:
                raise RuntimeError(f"{pid}: {field} changed since snapshot; stop")
        if pid in finished:
            recorded = next(row for row in receipt["products"] if row["productId"] == pid)
            if current["iconImageAssetId"] != recorded["afterIconImageAssetId"]:
                raise RuntimeError(f"{pid}: icon drift after recorded update; stop")
            print("Verified existing receipt", pid)
            continue
        if current["iconImageAssetId"] != OLD_ICON:
            raise RuntimeError(f"{pid}: icon changed since baseline, perhaps after an uncertain upload; stop")
        path = ROOT / "proposed" / filename
        with path.open("rb") as image:
            response = session.patch(
                f"{BASE}/{pid}",
                files={"imageFile": (filename, image, "image/png")},
                timeout=60,
            )
        response.raise_for_status()
        updated = None
        for _ in range(10):
            updated = compact(get(session, pid))
            if updated["iconImageAssetId"] != OLD_ICON:
                break
            time.sleep(2)
        if updated is None or updated["iconImageAssetId"] == OLD_ICON:
            raise RuntimeError(f"{pid}: PATCH returned success but icon change not visible; inspect before retry")
        for field in INVARIANT_FIELDS:
            if updated[field] != old[field]:
                raise RuntimeError(f"{pid}: PATCH unexpectedly changed {field}")
        receipt["products"].append({
            "productId": pid,
            "name": expected_name,
            "beforeIconImageAssetId": OLD_ICON,
            "afterIconImageAssetId": updated["iconImageAssetId"],
            "uploadedFile": f"proposed/{filename}",
            "uploadedSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "unchangedFields": list(INVARIANT_FIELDS),
        })
        save(receipt_path, receipt)
        print("Updated and verified", pid, "icon", OLD_ICON, "->", updated["iconImageAssetId"])

    after = {
        "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
        "universeId": UNIVERSE_ID,
        "products": {str(pid): compact(get(session, pid)) for pid, _, _ in PRODUCTS},
    }
    save(ROOT / "after-three-state.json", after)


if __name__ == "__main__":
    main()
