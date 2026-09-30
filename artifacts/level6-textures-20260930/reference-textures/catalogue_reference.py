"""Catalogue source-pack Level 3 images without accessing authentication data."""
from concurrent.futures import ThreadPoolExecutor
from pathlib import Path
import colorsys
import hashlib
import io
import json
import tarfile
import urllib.error
import urllib.request

from PIL import Image, ImageDraw, ImageFont, ImageStat

ROOT = Path(__file__).resolve().parents[3]
OUT = Path(__file__).resolve().parent
PACK = ROOT / "assets/source-packs/live-assets-2026-08-26/parts"
PACK_SHA = "4b083e73ec4606822299e245e2651f82dab48939a51f636aa5e9c6761405302e"
ENTRIES = [
    ("PartyCarpetTexture", 92795890253148, "party-carpet.png", 28),
    ("PartyCarpetNeonTexture", 110230144446272, "party-carpet-neon-v1.png", 22),
    ("PartyCarpetRedTexture", 108064770913201, "party-carpet-red-v1.png", 30),
    ("CityPlayCarpetTexture", 75635502248205, "city-play-carpet.png", 52),
    ("PastelWallpaperTexture", 96252806287644, "pastel-wallpaper.png", 18),
    ("OrangeWallTexture", 128270554927663, "orange-wall-worn-v1.png", 22),
    ("ConfettiTableclothTexture", 103412925025303, "confetti-tablecloth.png", 10),
    ("FinalExitDoorTexture", 120063024460642, "final-exit-blastdoor-v1.png", None),
    ("KidsDrawingsAtlasTexture", 136455642832077, "kids-drawings-atlas-transparent-v3.png", None),
    ("KidsDrawingsWholesome25Texture", 128767366284181, "kids-drawings-wholesome-25.png", None),
    ("KidsDrawingsDisturbing25Texture", 132144680342985, "kids-drawings-disturbing-25.png", None),
    ("KidsNotesAtlasTexture", 81550568434150, "kids-notes-atlas-transparent-v2.png", None),
    ("CDCoversAtlasTexture", 88160214591687, "cd-covers-atlas-v1.png", None),
    ("DiscPlayerPanelTexture", 92830391726737, "disk-player-surface.png", None),
    ("CRTScreenTexture", 106602270400755, "crt-screen-surface.png", None),
    ("MallManagerColorMap", 139917107442839, "mall-manager-color.png", None),
    ("FoldingTableTexture", 112282995723556, None, None),
]


def inspect_anonymous_delivery(entry):
    slot, asset_id, _, _ = entry
    url = "https://assetdelivery.roblox.com/v1/asset/?id=" + str(asset_id)
    try:
        request = urllib.request.Request(url, headers={"User-Agent": "Roblox/WinInet"})
        with urllib.request.urlopen(request, timeout=20) as response:
            data = response.read()
            return slot, {"url": url, "httpStatus": response.status, "bytes": len(data)}
    except urllib.error.HTTPError as error:
        body = error.read().decode("utf-8", errors="replace")
        return slot, {"url": url, "httpStatus": error.code, "error": body[:400]}
    except Exception as error:
        return slot, {"url": url, "error": str(error)[:200]}


def main():
    OUT.mkdir(parents=True, exist_ok=True)
    archive_bytes = b"".join(path.read_bytes() for path in sorted(PACK.glob("*.part-*")))
    archive_sha = hashlib.sha256(archive_bytes).hexdigest()
    assert archive_sha == PACK_SHA, "Original source archive integrity mismatch"
    archive = tarfile.open(fileobj=io.BytesIO(archive_bytes), mode="r:gz")
    prefix = "rblx-live-assets-2026-08-26-v2/"
    sums = archive.extractfile(prefix + "SHA256SUMS").read().decode()
    expected = {}
    for line in sums.splitlines():
        digest, name = line.split(maxsplit=1)
        expected[name.lstrip("*").removeprefix("./")] = digest
    with ThreadPoolExecutor(max_workers=6) as pool:
        anonymous_results = dict(pool.map(inspect_anonymous_delivery, ENTRIES))
    records = []
    thumbnails = []
    for slot, asset_id, filename, studs in ENTRIES:
        record = {"slot": slot, "assetId": asset_id, "textureUri": f"rbxassetid://{asset_id}",
                  "anonymousAssetDelivery": anonymous_results[slot], "studsPerTile": studs,
                  "liveStudioVerifiedThisTask": False}
        if filename is None:
            record.update(status="unavailable-local-source", note="Source archive does not contain this image. ID comes from historical live asset manifest; current template needs fresh Studio read.")
            records.append(record)
            continue
        member = "textures/level3/" + filename
        data = archive.extractfile(prefix + member).read()
        digest = hashlib.sha256(data).hexdigest()
        assert digest == expected[member], "Source file checksum mismatch: " + member
        destination = OUT / filename
        destination.write_bytes(data)
        with Image.open(io.BytesIO(data)) as source:
            source.load()
            pixels = source.convert("RGB")
            mean = ImageStat.Stat(pixels).mean
            sample = pixels.resize((128, 128), Image.Resampling.BOX)
            saturation = [colorsys.rgb_to_hsv(r / 255, g / 255, b / 255)[1] for r, g, b in sample.getdata()]
            saturation.sort()
            record.update(status="verified-original-source-pack", file=filename, bytes=len(data), sha256=digest,
                          imageSize=list(source.size), mode=source.mode, meanRGB=[round(x, 2) for x in mean],
                          medianHSVPixelSaturation=round(saturation[len(saturation) // 2], 4),
                          verification={"archiveSha256": archive_sha, "archiveMember": member,
                                        "memberSha256Matched": True,
                                        "assetIdMapping": "assets/live-asset-manifest.json liveAssetIds.level3Images / modelsAndAnimations",
                                        "limitation": "Historically verified source-to-ID mapping; anonymous delivery requires authentication and current live Studio read remains pending."})
            preview = source.convert("RGBA")
            preview.thumbnail((288, 250), Image.Resampling.LANCZOS)
            thumbnails.append((slot, asset_id, preview.copy(), studs))
        records.append(record)
    sheet = Image.new("RGB", (1280, 1320), (31, 29, 27))
    draw = ImageDraw.Draw(sheet)
    font = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 14)
    small = ImageFont.truetype("/System/Library/Fonts/Supplemental/Arial.ttf", 12)
    for index, (slot, asset_id, preview, studs) in enumerate(thumbnails):
        x, y = (index % 4) * 320, (index // 4) * 330
        draw.rounded_rectangle((x + 7, y + 7, x + 313, y + 320), radius=8, fill=(50, 47, 43))
        sheet.paste(preview, (x + (320 - preview.width) // 2, y + 20 + (250 - preview.height) // 2), preview)
        draw.text((x + 16, y + 277), slot, font=font, fill=(235, 230, 211))
        draw.text((x + 16, y + 297), str(asset_id) + (f" | {studs} studs" if studs else ""), font=small, fill=(180, 173, 150))
    sheet.save(OUT / "level3-textures-contact-sheet.jpg", quality=90)
    manifest = {"schemaVersion": 1, "task": "Level 6 texture restyle reference", "sourceArchiveSha256": archive_sha,
                "effectiveLiveTextureSlotsPending": True, "retrievedOriginalImageCount": len(thumbnails),
                "originalConfigurationImageCount": 15, "credentialsAccessed": False,
                "records": records}
    (OUT / "reference-manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
    print(json.dumps({"retrievedOriginalImages": len(thumbnails), "slotImages": 15,
                      "anonymousHttpStatuses": sorted(set(r["httpStatus"] for r in anonymous_results.values() if "httpStatus" in r)),
                      "sourceArchiveSha256": archive_sha, "contactSheet": str(OUT / "level3-textures-contact-sheet.jpg")}, indent=2))


if __name__ == "__main__":
    main()
