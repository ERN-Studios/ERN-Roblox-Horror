#!/usr/bin/env python3
"""Authenticated relay: Roblox game server -> private Discord webhook.

A Roblox game server cannot POST to discord.com (Discord answers 403 to Roblox's
HttpService user agent, which cannot be overridden), so the game posts here with
a bearer token and this forwards a Discord embed. The webhook URL lives only in
this process's environment -- never in the place file, never on a client.

Standard library only.  Env:
    RELAY_TOKEN           required, shared secret the game sends as "Bearer <t>"
    DISCORD_WEBHOOK_URL   required, the #dev-purchase-alerts webhook
    PORT                  default 8787
    DEDUPE_FILE           optional JSON file, remembers forwarded PurchaseIds
"""

from __future__ import annotations

import hmac
import json
import os
import sys
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, HTTPServer

MAX_BODY = 8192
DEDUPE_KEEP = 5000
FORWARD_ATTEMPTS = 2
FORWARD_TIMEOUT = 10

TOKEN = os.environ.get("RELAY_TOKEN", "")
WEBHOOK = os.environ.get("DISCORD_WEBHOOK_URL", "")
DEDUPE_FILE = os.environ.get("DEDUPE_FILE", "")

seen: list[str] = []
seen_set: set[str] = set()


def load_dedupe() -> None:
    if not DEDUPE_FILE or not os.path.exists(DEDUPE_FILE):
        return
    try:
        with open(DEDUPE_FILE, encoding="utf-8") as handle:
            stored = json.load(handle)
    except (OSError, ValueError):
        print("dedupe file unreadable; starting empty", flush=True)
        return
    for purchase_id in stored if isinstance(stored, list) else []:
        if isinstance(purchase_id, str) and purchase_id not in seen_set:
            seen.append(purchase_id)
            seen_set.add(purchase_id)


def remember(purchase_id: str) -> None:
    seen.append(purchase_id)
    seen_set.add(purchase_id)
    while len(seen) > DEDUPE_KEEP:
        seen_set.discard(seen.pop(0))
    if not DEDUPE_FILE:
        return
    try:
        with open(DEDUPE_FILE, "w", encoding="utf-8") as handle:
            json.dump(seen, handle)
    except OSError:
        print("dedupe file not writable; dedupe is memory-only", flush=True)


def embed(alert: dict) -> dict:
    robux = alert.get("robux")
    price = "STUDIO TEST (0)" if alert.get("test") else f"{robux} Robux"
    name = alert.get("productName") or alert.get("productKey") or "unknown product"
    return {
        "username": "Zyntra Purchases",
        "embeds": [{
            "title": "\N{MONEY BAG} NEW PURCHASE",
            "color": 0x2ECC71,
            "fields": [
                {"name": "Product", "value": f"{name} ({alert.get('productId')})", "inline": True},
                {"name": "Price", "value": price, "inline": True},
                {"name": "Player", "value": f"{alert.get('playerName')} ({alert.get('userId')})",
                 "inline": True},
                {"name": "Time", "value": f"{alert.get('timestamp')}", "inline": True},
                {"name": "Purchase ID", "value": f"`{alert.get('purchaseId')}`", "inline": False},
                {"name": "Place / Job", "value": f"{alert.get('placeId')} / {alert.get('jobId')}",
                 "inline": False},
            ],
        }],
    }


def forward(payload: dict) -> bool:
    """POST to Discord. Two tries; never logs the URL or the response body."""
    data = json.dumps(payload).encode("utf-8")
    for attempt in range(1, FORWARD_ATTEMPTS + 1):
        request = urllib.request.Request(
            WEBHOOK, data=data, headers={"Content-Type": "application/json"})
        try:
            with urllib.request.urlopen(request, timeout=FORWARD_TIMEOUT) as response:
                if 200 <= response.status < 300:
                    return True
                status = response.status
        except urllib.error.HTTPError as error:
            status = error.code
        except (urllib.error.URLError, OSError, ValueError):
            status = 0
        print(f"discord forward attempt {attempt} failed (status {status})", flush=True)
        if attempt < FORWARD_ATTEMPTS:
            time.sleep(1)
    return False


class Handler(BaseHTTPRequestHandler):
    server_version = "ZyntraPurchaseRelay/1.0"

    def log_message(self, fmt, *args):  # noqa: A002 - stdlib signature
        # Default logging prints the request line; here it never carries a token
        # (the token is a header) and the path is always "/". Keep it terse.
        print("%s %s" % (self.command, fmt % args if args else fmt), flush=True)

    def reply(self, status: int, text: str) -> None:
        body = text.encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "text/plain; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path.split("?", 1)[0] == "/healthz":
            self.reply(200, "ok")
        else:
            self.reply(404, "not found")

    def do_POST(self):
        if self.path.split("?", 1)[0] != "/":
            self.reply(404, "not found")
            return
        header = self.headers.get("Authorization", "")
        if not hmac.compare_digest(header, "Bearer " + TOKEN):
            self.reply(401, "unauthorized")
            return
        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            length = -1
        if length < 1 or length > MAX_BODY:
            self.reply(400, "bad body length")
            return
        try:
            alert = json.loads(self.rfile.read(length).decode("utf-8"))
        except (ValueError, UnicodeDecodeError):
            self.reply(400, "bad json")
            return
        purchase_id = alert.get("purchaseId") if isinstance(alert, dict) else None
        if not isinstance(purchase_id, str) or not purchase_id:
            self.reply(400, "missing purchaseId")
            return
        if purchase_id in seen_set:
            self.reply(202, "duplicate")
            return
        if forward(embed(alert)):
            remember(purchase_id)
            self.reply(200, "forwarded")
        else:
            # 5xx so the game server retries; the id is NOT remembered.
            self.reply(502, "discord unavailable")


def main() -> None:
    if not TOKEN or not WEBHOOK:
        sys.exit("Set RELAY_TOKEN and DISCORD_WEBHOOK_URL")
    load_dedupe()
    port = int(os.environ.get("PORT", "8787"))
    # ponytail: single-threaded; purchases arrive one at a time and each forward
    # is a sub-second POST. Swap in ThreadingHTTPServer (and a lock around the
    # dedupe list) only if a queue ever builds up.
    server = HTTPServer(("0.0.0.0", port), Handler)
    print(f"purchase alert relay listening on :{port} ({len(seen)} ids remembered)", flush=True)
    server.serve_forever()


if __name__ == "__main__":
    main()
