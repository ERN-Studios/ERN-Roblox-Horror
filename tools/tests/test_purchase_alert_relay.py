"""Exercise tools/purchase_alert_relay/relay.py over real HTTP.

The relay runs as a subprocess on a free localhost port; Discord is a fake
in-process HTTP server. No network, no real webhook, no Discord token.
"""

from __future__ import annotations

import json
import os
import socket
import subprocess
import sys
import tempfile
import threading
import time
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
RELAY = ROOT / "tools/purchase_alert_relay/relay.py"
TOKEN = "test-token-n0t-a-real-secret"

checks = 0


def check(condition, message):
    global checks
    checks += 1
    assert condition, message


def equal(actual, expected, message):
    check(actual == expected, f"{message}: expected {expected!r}, got {actual!r}")


def free_port() -> int:
    with socket.socket() as sock:
        sock.bind(("127.0.0.1", 0))
        return sock.getsockname()[1]


class FakeDiscord:
    """Records webhook posts; `status` drives what it answers."""

    def __init__(self):
        self.posts: list[dict] = []
        self.status = 204
        outer = self

        class Handler(BaseHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_POST(self):
                length = int(self.headers.get("Content-Length", "0"))
                outer.posts.append(json.loads(self.rfile.read(length).decode("utf-8")))
                self.send_response(outer.status)
                self.send_header("Content-Length", "0")
                self.end_headers()

        self.server = ThreadingHTTPServer(("127.0.0.1", 0), Handler)
        self.port = self.server.server_address[1]
        threading.Thread(target=self.server.serve_forever, daemon=True).start()

    @property
    def url(self) -> str:
        return f"http://127.0.0.1:{self.port}/hook"

    def stop(self):
        self.server.shutdown()


def post(port: int, payload, token: str = TOKEN, path: str = "/") -> int:
    body = payload if isinstance(payload, bytes) else json.dumps(payload).encode("utf-8")
    request = urllib.request.Request(
        f"http://127.0.0.1:{port}{path}", data=body,
        headers={"Content-Type": "application/json", "Authorization": f"Bearer {token}"})
    try:
        with urllib.request.urlopen(request, timeout=10) as response:
            return response.status
    except urllib.error.HTTPError as error:
        return error.code


def start_relay(discord_url: str, dedupe: Path | None) -> tuple[subprocess.Popen, int, list[str]]:
    port = free_port()
    env = dict(os.environ)
    env.update({"RELAY_TOKEN": TOKEN, "DISCORD_WEBHOOK_URL": discord_url, "PORT": str(port),
                "DEDUPE_FILE": str(dedupe) if dedupe else ""})
    process = subprocess.Popen([sys.executable, "-u", str(RELAY)], env=env,
                               stdout=subprocess.PIPE, stderr=subprocess.STDOUT, text=True)
    log: list[str] = []
    threading.Thread(target=lambda: [log.append(line) for line in process.stdout],
                     daemon=True).start()
    for _ in range(100):
        try:
            with urllib.request.urlopen(f"http://127.0.0.1:{port}/healthz", timeout=1) as response:
                if response.status == 200:
                    return process, port, log
        except (urllib.error.URLError, OSError):
            time.sleep(0.05)
    process.kill()
    raise SystemExit("relay did not start:\n" + "".join(log))


def alert(purchase_id: str, **overrides) -> dict:
    payload = {"purchaseId": purchase_id, "productId": 3707755089, "productKey": "Tokens4",
               "productName": "4 Research Tokens", "kind": "Utility", "robux": 49,
               "playerName": "SomePlayer", "userId": 40920547, "placeId": 111, "jobId": "job-a",
               "timestamp": "2026-09-14T10:11:12Z", "test": False}
    payload.update(overrides)
    return payload


def main():
    discord = FakeDiscord()
    logs: list[list[str]] = []
    with tempfile.TemporaryDirectory(prefix="purchase-relay-") as directory:
        dedupe = Path(directory) / "seen.json"
        relay, port, log = start_relay(discord.url, dedupe)
        logs.append(log)
        try:
            equal(post(port, alert("p1"), token="wrong"), 401, "bad token rejected")
            equal(len(discord.posts), 0, "rejected request forwards nothing")

            equal(post(port, alert("p1")), 200, "authenticated alert accepted")
            equal(len(discord.posts), 1, "accepted alert forwarded once")
            fields = {f["name"]: f["value"] for f in discord.posts[0]["embeds"][0]["fields"]}
            check("NEW PURCHASE" in discord.posts[0]["embeds"][0]["title"], "embed titled")
            equal(fields["Product"], "4 Research Tokens (3707755089)", "product name and id")
            equal(fields["Price"], "49 Robux", "actual Robux paid")
            equal(fields["Player"], "SomePlayer (40920547)", "player name and userId")
            equal(fields["Time"], "2026-09-14T10:11:12Z", "timestamp")
            equal(fields["Purchase ID"], "`p1`", "PurchaseId for dedupe")
            equal(fields["Place / Job"], "111 / job-a", "place and job id")

            equal(post(port, alert("p1", robux=999)), 202, "duplicate PurchaseId accepted quietly")
            equal(len(discord.posts), 1, "duplicate PurchaseId forwards nothing")

            equal(post(port, alert("p2", test=True, robux=0)), 200, "studio alert accepted")
            price = {f["name"]: f["value"] for f in discord.posts[1]["embeds"][0]["fields"]}["Price"]
            equal(price, "STUDIO TEST (0)", "studio purchase is labelled, not priced")

            equal(post(port, b"{not json"), 400, "unparseable body rejected")
            equal(post(port, {"productId": 1}), 400, "missing purchaseId rejected")
            equal(post(port, alert("p3"), path="/anything"), 404, "only / accepts alerts")
            equal(len(discord.posts), 2, "rejected bodies forward nothing")

            discord.status = 500
            equal(post(port, alert("p4")), 502, "Discord failure reported so Roblox retries")
            equal(len(discord.posts), 4, "failed forward is attempted twice")
            discord.status = 204
            equal(post(port, alert("p4")), 200, "failed PurchaseId is not remembered")
            equal(len(discord.posts), 5, "retry of a failed alert reaches Discord")

            relay.terminate()
            relay.wait(timeout=10)

            stored = json.loads(dedupe.read_text(encoding="utf-8"))
            check("p1" in stored and "p4" in stored, "forwarded ids persisted")
            check("p3" not in stored, "rejected ids not persisted")

            relay, port, log = start_relay(discord.url, dedupe)
            logs.append(log)
            equal(post(port, alert("p1")), 202, "dedupe survives a restart")
            equal(len(discord.posts), 5, "restarted relay forwards no duplicate")
            equal(post(port, alert("p5")), 200, "restarted relay still forwards new ids")
        finally:
            relay.terminate()
            relay.wait(timeout=10)
            discord.stop()

    time.sleep(0.2)
    text = "".join(line for lines in logs for line in lines)
    check(TOKEN not in text, "relay never logs the token")
    check(discord.url not in text and "/hook" not in text, "relay never logs the webhook URL")
    print(f"purchase alert relay: {checks} checks passed")


if __name__ == "__main__":
    main()
