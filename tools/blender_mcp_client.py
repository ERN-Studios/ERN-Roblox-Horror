"""Small client for Blender's official localhost MCP bridge.

The Blender add-on accepts null-byte-delimited JSON on localhost:9876.  Keeping
the transport here makes animation build scripts operate on the user's open,
current Blender scene instead of a stale on-disk copy.
"""

from __future__ import annotations

import json
import socket
from typing import Any


def execute(code: str, host: str = "127.0.0.1", port: int = 9876,
            timeout: float = 120.0) -> dict[str, Any]:
    request = {
        "type": "execute",
        "strict_json": True,
        "code": code,
    }
    wire = json.dumps(request).encode("utf-8") + b"\0"
    response = bytearray()
    with socket.create_connection((host, port), timeout=10) as client:
        client.settimeout(timeout)
        client.sendall(wire)
        while b"\0" not in response:
            chunk = client.recv(65536)
            if not chunk:
                raise ConnectionError("Blender MCP closed before returning a response")
            response.extend(chunk)
    payload = json.loads(bytes(response[:response.index(0)]).decode("utf-8"))
    if payload.get("status") != "ok":
        raise RuntimeError(payload.get("message", "Unknown Blender MCP error"))
    return payload

