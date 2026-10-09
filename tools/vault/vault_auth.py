"""Resolve the local Obsidian bearer credential only when a request needs it."""

import json
import os
from pathlib import Path


ENV_TOKEN = "MONGOTV_OBSIDIAN_MCP_TOKEN"
CONFIG_PATH = (
    Path(__file__).resolve().parents[2]
    / "Backrooms Stay Quiet"
    / ".obsidian/plugins/mcp-tools-istefox/data.json"
)


def _header_token(token):
    if any(ord(character) < 32 or ord(character) > 126 for character in token):
        raise RuntimeError("Obsidian bearer credential contains unsupported HTTP header characters")
    return token


def get_token():
    """Use an explicit environment override or the existing vault plugin setting."""
    override = os.environ.get(ENV_TOKEN)
    if override is not None:
        if not override.strip():
            raise RuntimeError(f"{ENV_TOKEN} must be nonempty")
        return _header_token(override)

    try:
        config = json.loads(CONFIG_PATH.read_text(encoding="utf-8-sig"))
    except (OSError, UnicodeError, json.JSONDecodeError):
        raise RuntimeError(
            f"Cannot read Obsidian credential configuration; configure the vault plugin or {ENV_TOKEN}"
        ) from None

    transport = config.get("mcpTransport") if isinstance(config, dict) else None
    token = transport.get("bearerToken") if isinstance(transport, dict) else None
    if not isinstance(token, str) or not token.strip():
        raise RuntimeError(
            f"Obsidian mcpTransport.bearerToken must be nonempty; configure the vault plugin or {ENV_TOKEN}"
        )
    return _header_token(token)
