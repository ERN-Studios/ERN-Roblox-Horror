"""Read-only audit of live Developer Product thumbnails in this experience.

The Roblox key is read from the local secret file. CDN URLs and credentials are
never recorded. This script does not write to Roblox.
"""

from __future__ import annotations

import hashlib
import io
import json
from datetime import datetime, timezone
from pathlib import Path

import requests
from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parent
UNIVERSE_ID = 10559217407
PRODUCT_URL = (
    f"https://apis.roblox.com/developer-products/v2/universes/{UNIVERSE_ID}"
    "/developer-products/creator"
)
# The official Developer Product thumbnail endpoint currently returns an empty
# `data` list for these Open Cloud product IDs. The linked icon asset IDs do
# resolve through the official asset thumbnail endpoint, so use those pixels
# and emulate the circular clipping that the Roblox product UI applies.
THUMBNAIL_URL = "https://thumbnails.roblox.com/v1/assets"
KEY_FILE = Path.home() / ".codex" / "secrets" / "roblox.env"


def api_key() -> str:
    for line in KEY_FILE.read_text(encoding="utf-8-sig").splitlines():
        if line.startswith("ROBLOX_API_KEY="):
            return line.partition("=")[2].strip().strip('"').strip("'")
    raise RuntimeError("ROBLOX_API_KEY not found")


def products(session: requests.Session) -> list[dict]:
    rows = []
    token = None
    while True:
        params = {"pageToken": token} if token else None
        response = session.get(PRODUCT_URL, params=params, timeout=30)
        response.raise_for_status()
        data = response.json()
        rows.extend(data["developerProducts"])
        token = data.get("nextPageToken")
        if not token:
            return rows


def thumbnail_map(session: requests.Session, ids: list[int]) -> dict[int, dict]:
    response = session.get(
        THUMBNAIL_URL,
        params={
            "assetIds": ",".join(map(str, ids)),
            "size": "150x150",
            "format": "Png",
            "isCircular": "false",
        },
        timeout=30,
    )
    response.raise_for_status()
    return {int(item["targetId"]): item for item in response.json()["data"]}


def safe_name(item: dict) -> str:
    name = "".join(c.lower() if c.isalnum() else "-" for c in item["name"])
    return "-".join(part for part in name.split("-") if part)[:40]


def font(size: int) -> ImageFont.ImageFont:
    path = Path("C:/Windows/Fonts/arial.ttf")
    return ImageFont.truetype(str(path), size) if path.exists() else ImageFont.load_default()


def main() -> None:
    session = requests.Session()
    session.headers["x-api-key"] = api_key()
    live = products(session)
    icon_ids = sorted({int(item["iconImageAssetId"]) for item in live if item.get("iconImageAssetId")})
    thumbs = thumbnail_map(session, icon_ids)
    target = ROOT / "live-thumbnails"
    target.mkdir(parents=True, exist_ok=True)
    rows = []
    for item in live:
        pid = int(item["productId"])
        row = {
            "productId": pid,
            "name": item["name"],
            "iconImageAssetId": item.get("iconImageAssetId"),
            "isForSale": item["isForSale"],
            "defaultPriceInRobux": item.get("priceInformation", {}).get("defaultPriceInRobux"),
            "thumbnails": {},
        }
        for shape in ("square", "circle"):
            info = thumbs.get(int(item["iconImageAssetId"]))
            if not info or info.get("state") != "Completed" or not info.get("imageUrl"):
                row["thumbnails"][shape] = {"state": info.get("state") if info else "Missing"}
                continue
            response = session.get(info["imageUrl"], timeout=30)
            response.raise_for_status()
            raw = response.content
            image = Image.open(io.BytesIO(raw)).convert("RGBA")
            if shape == "circle":
                mask = Image.new("L", image.size, 0)
                ImageDraw.Draw(mask).ellipse((0, 0, image.width - 1, image.height - 1), fill=255)
                image.putalpha(mask)
            # Save the exact live thumbnail bytes for evidence, plus a normalized
            # 128px version for a fair side-by-side visual comparison.
            original = target / f"{pid}-{safe_name(item)}-{shape}-150.png"
            image.save(original)
            normalized = target / f"{pid}-{shape}-128.png"
            image.resize((128, 128), Image.Resampling.LANCZOS).save(normalized)
            row["thumbnails"][shape] = {
                "state": info["state"],
                "file": original.relative_to(ROOT).as_posix(),
                "previewFile": normalized.relative_to(ROOT).as_posix(),
                "sha256": hashlib.sha256(original.read_bytes()).hexdigest(),
                "sourceIconAssetId": int(item["iconImageAssetId"]),
            }
        rows.append(row)

    out = {
        "capturedAtUtc": datetime.now(timezone.utc).isoformat(),
        "universeId": UNIVERSE_ID,
        "source": "Roblox Open Cloud creator product list and official asset thumbnail API",
        "cropMethod": "Product thumbnail API returned no data; circle preview is local mask of live icon asset thumbnail",
        "products": rows,
    }
    (ROOT / "inventory.json").write_text(json.dumps(out, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")

    width, height = 930, 832
    sheet = Image.new("RGB", (width, height), "#161c20")
    draw = ImageDraw.Draw(sheet)
    title = font(18)
    body = font(14)
    small = font(12)
    for index, row in enumerate(rows):
        col, line = index % 3, index // 3
        x, y = 12 + col * 310, 12 + line * 202
        draw.rounded_rectangle((x, y, x + 298, y + 188), radius=12, fill="#242d32")
        name = row["name"]
        if len(name) > 31:
            name = name[:28] + "..."
        draw.text((x + 8, y + 5), name, font=body, fill="white")
        draw.text((x + 8, y + 24), f"{row['productId']}  |  {row['defaultPriceInRobux']} R$", font=small, fill="#b8c6c9")
        for offset, shape in ((6, "square"), (155, "circle")):
            preview = row["thumbnails"].get(shape, {}).get("previewFile")
            if preview:
                image = Image.open(ROOT / preview).convert("RGBA")
                background = Image.new("RGBA", image.size, "#313d42")
                background.alpha_composite(image)
                sheet.paste(background.convert("RGB"), (x + offset, y + 47))
        draw.text((x + 50, y + 173), "square", font=small, fill="#b8c6c9")
        draw.text((x + 195, y + 173), "circle preview", font=small, fill="#b8c6c9")
    draw.text((14, height - 14), "Official live thumbnails, captured 2026-09-24", font=small, fill="#b8c6c9")
    sheet.save(ROOT / "all-developer-products-128-preview.png")
    print(f"Captured {len(rows)} Developer Products; inventory and 128px crop sheet written to {ROOT}")


if __name__ == "__main__":
    main()
