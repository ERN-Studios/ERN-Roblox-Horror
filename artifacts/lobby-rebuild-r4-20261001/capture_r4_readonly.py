"""Bounded direct official StudioMCP read-only client for lobby R4 exports."""
from __future__ import annotations

import argparse
import json
import queue
import subprocess
import threading
import time
from pathlib import Path


class Client:
    def __init__(self):
        self.queue = queue.Queue()
        self.process = subprocess.Popen(
            ["/Applications/RobloxStudio.app/Contents/MacOS/StudioMCP"],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE,
            text=True, bufsize=1,
        )
        self.next_id = 0
        threading.Thread(target=self._read, args=(self.process.stdout,), daemon=True).start()
        # Suppress native diagnostics rather than risk emitting session contents.
        threading.Thread(target=self._discard, args=(self.process.stderr,), daemon=True).start()

    def _read(self, stream):
        for line in stream:
            try: self.queue.put(json.loads(line))
            except json.JSONDecodeError: continue

    @staticmethod
    def _discard(stream):
        for _ in stream: pass

    def request(self, method, params, timeout=50):
        self.next_id += 1
        identifier = self.next_id
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "id": identifier,
                                            "method": method, "params": params}) + "\n")
        self.process.stdin.flush()
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            try: message = self.queue.get(timeout=.2)
            except queue.Empty: continue
            if message.get("id") == identifier:
                if "error" in message: raise RuntimeError(message["error"])
                return message["result"]
        raise TimeoutError(f"Official StudioMCP read timed out: {method}")

    def initialize(self):
        result = self.request("initialize", {"protocolVersion": "2024-11-05",
                              "capabilities": {}, "clientInfo": {"name": "LobbyR4ReadonlyCapture", "version": "1"}})
        self.process.stdin.write(json.dumps({"jsonrpc": "2.0", "method": "notifications/initialized", "params": {}}) + "\n")
        self.process.stdin.flush()
        return result

    def tool(self, name, arguments, timeout=50):
        return self.request("tools/call", {"name": name, "arguments": arguments}, timeout)

    def close(self):
        self.process.terminate()
        try: self.process.wait(timeout=2)
        except subprocess.TimeoutExpired: self.process.kill()


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--inventory", action="store_true")
    parser.add_argument("--code", type=Path)
    parser.add_argument("--output", type=Path)
    args = parser.parse_args()
    client = Client()
    try:
        result = client.initialize()
        if args.inventory:
            print(json.dumps({"server": result.get("serverInfo"),
                              "tools": client.request("tools/list", {})}, indent=2))
        elif args.code:
            result = client.tool("execute_luau", {"studio_id": "08b776ed-0330-44f6-8378-c6eea82b3f38",
                                                  "datamodel_type": "Edit", "code": args.code.read_text()}, timeout=55)
            if args.output:
                args.output.parent.mkdir(parents=True, exist_ok=True)
                args.output.write_text(json.dumps(result, indent=2) + "\n")
            print(json.dumps({"isError": result.get("isError", False), "content": result.get("content", [])}, indent=2))
        else:
            print(json.dumps(client.tool("list_roblox_studios", {}), indent=2))
    finally:
        client.close()


if __name__ == "__main__": main()
