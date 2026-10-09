"""Turn a Roblox sales export into the ServerStorage.ZyntraSalesBackfill module
that ZyntraMonetization's historical sales import reads (Trello #36).

The export's "Asset Id" is NOT the catalogue id the game prompts with -- Roblox
reports a developer product by its product id, while ZyntraConfig holds the id
passed to PromptProductPurchase. The mapping below is therefore explicit and
closed: an asset id this file does not know aborts the run instead of being
guessed into a stream, because a wrong stream would silently reconcile a
purchase against the wrong audited stream.

Gross "Price" is what a player spent; "Revenue" is the creator's cut after
Roblox's fee and is never used. Status Pending and Paid are both completed
sales (Pending is the creator payout, not the buyer's payment).

Usage:
    python tools/leaderboard_backfill/generate_backfill.py \
        _local/trello-20260915/sales.csv \
        _local/trello-20260915/ZyntraSalesBackfill_20260915.ModuleScript.lua \
        --source-key sales_20260915 \
        --profile-audit _local/trello-20260915/live-profile-audit.json

Output stays under _local/: it carries buyer user ids.
"""

import argparse
import csv
import datetime
import hashlib
import io
import json
import pathlib
import sys

UNIVERSE_ID = "10559217407"
COMPLETED_STATUSES = {"Pending", "Paid"}

# CSV asset id -> (stream, catalogue key, catalogue id, name). The catalogue
# columns are documentation: nothing downstream reads them, they are here so the
# identity mismatch is reviewable.
ASSET_STREAMS = {
    "77345358": ("utility", "Config.Products.Reentry", 3707755318, "Emergency Re-entry"),
    "77665692": ("donation", "Config.Donations.Signal", 3710116814, "ZYNTRA Donate - Signal"),
    "1941938256": ("pass", "Config.Passes.Supporter", 1941938256, "Zyntra Supporter"),
    # Sold on the storefront, deliberately absent from the in-game catalogue.
    "1978617781": ("pass", None, 1978617781, "ZYNTRA Support - 20K"),
}
# Private server products are keyed by the universe id, so they are recognised by
# type rather than by asset id, and they repeat: one row per server bought.
TYPE_STREAMS = {"Private Server Product": "pass"}
# Streams ProcessReceipt also writes. Corrected by the audited historical delta.
LIVE_STREAMS = {"utility", "donation"}


def classify(row):
    """(stream, marker) for a row, or raise on anything unmapped."""
    asset_type = row["Asset Type"]
    asset_id = row["Asset Id"]
    stream = TYPE_STREAMS.get(asset_type)
    if stream is None:
        known = ASSET_STREAMS.get(asset_id)
        if known is None:
            raise SystemExit(
                f"Unmapped {asset_type} asset id {asset_id} ({row['Asset Name']!r}). "
                "Add it to ASSET_STREAMS with its catalogue key before importing."
            )
        stream = known[0]
    # A game pass is owned at most once per account, so keying its marker by the
    # pass id -- not by the export row -- is what stops a future live pass
    # detector counting the same 99 R$ again on top of this import.
    marker = f"pass:{asset_id}" if asset_type == "Game Pass" else f"row:{row['Id']}"
    return stream, marker


def whole(value):
    number = float(value)
    if number != int(number):
        raise ValueError(f"non-integer Robux amount {value!r}")
    return int(number)


def lua_string(value):
    return '"' + value.replace("\\", "\\\\").replace('"', '\\"') + '"'


def build(csv_path, source_key):
    raw = csv_path.read_bytes()
    sha = hashlib.sha256(raw).hexdigest()
    reader = csv.DictReader(io.StringIO(raw.decode("utf-8-sig")))
    rows, skipped, seen = [], [], set()
    for line, row in enumerate(reader, start=2):
        csv_id = row["Id"]
        try:
            if row["Universe Id"] != UNIVERSE_ID:
                raise ValueError(f"foreign universe {row['Universe Id']}")
            if row["Status"] not in COMPLETED_STATUSES:
                raise ValueError(f"status {row['Status']!r} is not a completed sale")
            if csv_id in seen:
                raise ValueError("duplicate export Id")
            user_id = int(row["Buyer User Id"])
            if user_id <= 0:
                raise ValueError("non-positive buyer id")
            price = whole(row["Price"])
            if price < 0:
                raise ValueError("negative price")
            stream, marker = classify(row)
        except ValueError as error:
            skipped.append(f"line {line}: {error}")
            continue
        seen.add(csv_id)
        rows.append(
            {
                "UserId": user_id,
                "AssetId": int(row["Asset Id"]),
                "AssetType": row["Asset Type"],
                "Price": price,
                "Time": row["Date and Time"],
                "CsvId": csv_id,
                "Stream": stream,
                "Marker": marker,
            }
        )
    return sha, rows, skipped


def render(source_key, sha, csv_name, rows, baselines):
    generated = datetime.datetime.now(datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
    out = [
        "-- ZyntraSalesBackfill -- GENERATED, do not hand-edit.",
        f"-- tools/leaderboard_backfill/generate_backfill.py from {csv_name}",
        "-- Server-only: this module carries buyer user ids and must never be",
        "-- reachable from a client. Place it in ServerStorage as",
        "-- ZyntraSalesBackfill, let one live server import it, then remove it.",
        "return {",
        f"\tSourceKey = {lua_string(source_key)},",
        f"\tSha256 = {lua_string(sha)},",
        f"\tGeneratedAt = {lua_string(generated)},",
        f"\tRowCount = {len(rows)},",
        "\tRows = {",
    ]
    for row in rows:
        out.append(
            "\t\t{{UserId = {UserId}, AssetId = {AssetId}, AssetType = {AssetType}, "
            "Price = {Price}, Time = {Time}, CsvId = {CsvId}, Stream = {Stream}, "
            "Marker = {Marker}}},".format(
                UserId=row["UserId"],
                AssetId=row["AssetId"],
                AssetType=lua_string(row["AssetType"]),
                Price=row["Price"],
                Time=lua_string(row["Time"]),
                CsvId=lua_string(row["CsvId"]),
                Stream=lua_string(row["Stream"]),
                Marker=lua_string(row["Marker"]),
            )
        )
    out += ["\t},", "\tBaselines = {"]
    for user_id, baseline in sorted(baselines.items()):
        receipts = ", ".join(lua_string(v) for v in baseline["ReceiptIds"])
        out.append("\t\t[" + lua_string(user_id) + "] = {DonationRobux = " + str(baseline["DonationRobux"])
                   + ", UtilityRobux = " + str(baseline["UtilityRobux"]) + ", ReceiptIds = {" + receipts + "}},")
    out += ["\t},", "}", ""]
    return "\n".join(out)


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("csv", type=pathlib.Path)
    parser.add_argument("out", type=pathlib.Path)
    parser.add_argument("--source-key", required=True)
    parser.add_argument("--expect-sha256", default=None)
    parser.add_argument("--profile-audit", type=pathlib.Path, required=True)
    args = parser.parse_args(argv)

    sha, rows, skipped = build(args.csv, args.source_key)
    if skipped:
        raise SystemExit("Refusing partial export: " + "; ".join(skipped))
    audit = json.loads(args.profile_audit.read_text(encoding="utf-8"))
    baselines = {r[0]: {"DonationRobux": r[2], "UtilityRobux": r[3], "ReceiptIds": r[4]} for r in audit}
    if len(baselines) != len(audit) or set(baselines) != {str(r["UserId"]) for r in rows}:
        raise SystemExit("Audit buyers must exactly match export buyers")
    for user_id, baseline in baselines.items():
        products = [r for r in rows if str(r["UserId"]) == user_id and r["Stream"] in LIVE_STREAMS]
        if len(baseline["ReceiptIds"]) != len(products) or len(set(baseline["ReceiptIds"])) != len(products):
            raise SystemExit("Receipt-count audit mismatch: " + user_id)
        for stream, field in [("donation", "DonationRobux"), ("utility", "UtilityRobux")]:
            total = sum(r["Price"] for r in products if r["Stream"] == stream)
            if not isinstance(baseline[field], int) or not 0 <= baseline[field] <= total:
                raise SystemExit("Invalid audited total: " + user_id + " " + field)
    if args.expect_sha256 and sha != args.expect_sha256:
        raise SystemExit(f"CSV sha256 {sha} != expected {args.expect_sha256}")
    if "_local" not in args.out.as_posix().split("/"):
        raise SystemExit("refusing to write buyer data outside _local/")
    args.out.parent.mkdir(parents=True, exist_ok=True)
    args.out.write_text(render(args.source_key, sha, args.csv.name, rows, baselines), encoding="utf-8", newline="\n")

    streams = {}
    for row in rows:
        entry = streams.setdefault(row["Stream"], [0, 0])
        entry[0] += 1
        entry[1] += row["Price"]
    print(f"source {args.source_key} sha256 {sha}")
    print(f"{len(rows)} rows kept, {len(skipped)} skipped, {len({r['UserId'] for r in rows})} buyers")
    for stream in sorted(streams):
        count, total = streams[stream]
        how = "audited baseline correction" if stream in LIVE_STREAMS else "added once by row marker"
        print(f"  {stream:<9} {count:>3} rows {total:>6} R$  ({how})")
    for note in skipped:
        print(f"  skipped {note}")
    print(f"wrote {args.out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
