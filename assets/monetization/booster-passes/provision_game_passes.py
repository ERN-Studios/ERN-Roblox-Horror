"""Idempotently provision the six approved Token Earner passes via Open Cloud.

New passes are deliberately off sale until the game code has been published.
The API key is read locally and never written to the receipt or stdout.
"""

import argparse
import json
from datetime import datetime, timezone
from pathlib import Path

import requests

UNIVERSE = 10559217407
BASE = f"https://apis.roblox.com/game-passes/v1/universes/{UNIVERSE}/game-passes"
ROOT = Path(__file__).resolve().parent
RECEIPT = ROOT / "game-pass-receipt.json"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"

PASSES = (
    ("Token Earner 2x", 149, "2x", "Permanent 2x multiplier for future earned Tokens. Does not affect your current balance or purchased Token packs."),
    ("Token Earner 3x", 299, "3x", "Permanent 3x multiplier for future earned Tokens. Does not affect your current balance or purchased Token packs."),
    ("Token Earner 5x", 399, "5x", "Permanent 5x multiplier for future earned Tokens. Does not affect your current balance or purchased Token packs."),
    ("Token Earner Upgrade 2x to 3x", 150, "3x", "Requires Token Earner 2x. Together they permanently grant 3x on future earned Tokens. This pass alone grants no boost."),
    ("Token Earner Upgrade 3x to 5x", 100, "5x", "Requires effective 3x from Token Earner 3x or 2x plus the 2x-to-3x upgrade. Together they grant 5x. This pass alone grants no boost."),
    ("Token Earner Upgrade 2x to 5x", 250, "5x", "Requires Token Earner 2x. Together they permanently grant 5x on future earned Tokens. This pass alone grants no boost."),
)


def read_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            key = line.partition("=")[2].strip().strip('"').strip("'")
            if key:
                return key
    raise RuntimeError("ROBLOX_API_KEY unavailable in local roblox.env")


def list_passes(session: requests.Session) -> dict[str, dict]:
    found = {}
    token = None
    while True:
        params = {"pageSize": 100}
        if token:
            params["pageToken"] = token
        response = session.get(BASE + "/creator", params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        for item in data.get("gamePasses", []):
            found[item["name"]] = item
        token = data.get("nextPageToken")
        if not token:
            return found


def save_receipt(passes: dict[str, dict]) -> None:
    summary = {
        "universeId": UNIVERSE,
        "checkedAtUtc": datetime.now(timezone.utc).isoformat(),
        "saleStatus": "off sale until published implementation passes QA",
        "passes": [
            {
                "name": name,
                "gamePassId": passes[name]["gamePassId"],
                "priceRobuxApproved": price,
                "iconAssetId": passes[name].get("iconAssetId"),
                "isForSale": passes[name].get("isForSale"),
                "priceInformation": passes[name].get("priceInformation"),
            }
            for name, price, _, _ in PASSES
            if name in passes
        ],
    }
    RECEIPT.write_text(json.dumps(summary, indent=2) + "\n", encoding="utf-8")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--create", action="store_true", help="create missing passes, initially off sale")
    args = parser.parse_args()
    session = requests.Session()
    session.headers["x-api-key"] = read_key()
    existing = list_passes(session)
    print(f"Found {len(existing)} existing passes; {sum(name in existing for name, *_ in PASSES)}/6 Token Earner passes already exist.")
    for name, price, tier, description in PASSES:
        if name in existing:
            print(f"EXISTS {name}: {existing[name]['gamePassId']}")
            continue
        if not args.create:
            print(f"WOULD CREATE {name}: {price} Robux, off sale")
            continue
        icon = ROOT / f"earned-tokens-{tier}-round.png"
        with icon.open("rb") as image:
            response = session.post(
                BASE,
                data={
                    "name": name,
                    "description": description,
                    "isForSale": "false",
                    "price": str(price),
                    "isManagedPricingEnabled": "false",
                },
                files={"imageFile": (icon.name, image, "image/png")},
                timeout=60,
            )
        if not response.ok:
            print(f"CREATE FAILED {name}: HTTP {response.status_code} {response.text[:500]}")
            raise SystemExit(1)
        item = response.json()
        print(f"CREATED {name}: {item.get('gamePassId')}")
        existing = list_passes(session)
        if name not in existing:
            raise RuntimeError(f"Created {name}, but it was not returned by the creator list")
        save_receipt(existing)
    save_receipt(existing)


if __name__ == "__main__":
    main()
