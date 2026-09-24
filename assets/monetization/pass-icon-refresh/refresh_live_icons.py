"""Capture, replace, and verify only four Game Pass thumbnail images.

Run the three stages separately: before, apply, after. The API key is read
from the local secret file and never written to receipts or output.
"""

import argparse
import hashlib
import json
from datetime import datetime, timezone
from pathlib import Path

import requests


ROOT = Path(__file__).resolve().parent
BASE = "https://apis.roblox.com/game-passes/v1/universes/10559217407/game-passes"
THUMBNAILS = "https://thumbnails.roblox.com/v1/game-passes"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"
PASSES = {
    "static-wraith": (1994666374, "static-wraith-round-v2.png"),
    "false-sun": (1994816385, "false-sun-round-v2.png"),
    "entity-detector": (1982715834, "entity-detector-round-v2.png"),
    "donation-20k": (1978617781, "donation-20k-round-v2.png"),
}
IMMUTABLE_IN_THIS_TASK = (
    "gamePassId", "name", "description", "isForSale", "priceInformation", "isManagedPricingEnabled"
)


def read_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            return line.partition("=")[2].strip().strip('"').strip("'")
    raise RuntimeError("ROBLOX_API_KEY unavailable")


def pass_url(pass_id: int) -> str:
    return f"{BASE}/{pass_id}"


def get_pass(session: requests.Session, pass_id: int) -> dict:
    response = session.get(pass_url(pass_id) + "/creator", timeout=30)
    response.raise_for_status()
    return response.json()


def get_thumbnail(session: requests.Session, pass_id: int, circular: bool) -> tuple[dict, bytes]:
    response = session.get(
        THUMBNAILS,
        params={
            "gamePassIds": str(pass_id),
            "size": "150x150",
            "format": "Png",
            "isCircular": str(circular).lower(),
        },
        timeout=30,
    )
    response.raise_for_status()
    item = response.json()["data"][0]
    if item["state"] != "Completed" or not item.get("imageUrl"):
        raise RuntimeError(f"Thumbnail {pass_id} circular={circular}: {item['state']}")
    image = session.get(item["imageUrl"], timeout=30)
    image.raise_for_status()
    return item, image.content


def snapshot(session: requests.Session, stage: str) -> None:
    target = ROOT / stage
    target.mkdir(exist_ok=True)
    rows = []
    for slug, (pass_id, filename) in PASSES.items():
        info = get_pass(session, pass_id)
        row = {field: info.get(field) for field in IMMUTABLE_IN_THIS_TASK}
        row["iconAssetId"] = info.get("iconAssetId")
        row["proposedFile"] = filename
        row["thumbnails"] = {}
        for circular in (False, True):
            label = "circle" if circular else "square"
            item, image = get_thumbnail(session, pass_id, circular)
            name = f"{slug}-{label}-150.png"
            (target / name).write_bytes(image)
            row["thumbnails"][label] = {
                "state": item["state"],
                "file": f"{stage}/{name}",
                "sha256": hashlib.sha256(image).hexdigest(),
            }
        rows.append(row)
        print(stage, slug, pass_id, "icon", row["iconAssetId"])
    output = {
        "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
        "universeId": 10559217407,
        "source": "Roblox Open Cloud Game Pass creator GET and official thumbnails API",
        "passes": rows,
    }
    (ROOT / f"{stage}-state.json").write_text(json.dumps(output, indent=2) + "\n", encoding="utf-8")


def apply(session: requests.Session) -> None:
    receipt = ROOT / "before-state.json"
    if not receipt.exists():
        raise RuntimeError("Capture before state first")
    before = {row["gamePassId"]: row for row in json.loads(receipt.read_text(encoding="utf-8"))["passes"]}
    result = {"appliedAtUtc": datetime.now(timezone.utc).isoformat(), "passes": []}
    for slug, (pass_id, filename) in PASSES.items():
        current = get_pass(session, pass_id)
        old = before[pass_id]
        if current.get("iconAssetId") != old["iconAssetId"]:
            raise RuntimeError(f"{slug}: icon changed after before-state capture; stop and inspect")
        for field in IMMUTABLE_IN_THIS_TASK:
            if current.get(field) != old.get(field):
                raise RuntimeError(f"{slug}: {field} changed after before-state capture; stop and inspect")
        path = ROOT / filename
        with path.open("rb") as image:
            response = session.patch(
                pass_url(pass_id),
                files={"imageFile": (filename, image, "image/png")},
                timeout=60,
            )
        response.raise_for_status()
        updated = get_pass(session, pass_id)
        for field in IMMUTABLE_IN_THIS_TASK:
            if updated.get(field) != old.get(field):
                raise RuntimeError(f"{slug}: PATCH unexpectedly changed {field}")
        if updated.get("iconAssetId") == old["iconAssetId"]:
            raise RuntimeError(f"{slug}: iconAssetId did not change after PATCH")
        row = {
            "slug": slug,
            "gamePassId": pass_id,
            "beforeIconAssetId": old["iconAssetId"],
            "afterIconAssetId": updated["iconAssetId"],
            "uploadedFile": filename,
            "uploadedSha256": hashlib.sha256(path.read_bytes()).hexdigest(),
            "unchangedFields": list(IMMUTABLE_IN_THIS_TASK),
        }
        result["passes"].append(row)
        (ROOT / "apply-receipt.json").write_text(json.dumps(result, indent=2) + "\n", encoding="utf-8")
        print("PATCHED", slug, pass_id, old["iconAssetId"], "->", updated["iconAssetId"])


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("stage", choices=("before", "apply", "after"))
    args = parser.parse_args()
    session = requests.Session()
    session.headers["x-api-key"] = read_key()
    if args.stage == "apply":
        apply(session)
    else:
        snapshot(session, args.stage)


if __name__ == "__main__":
    main()
