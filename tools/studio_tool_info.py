"""Print selected Roblox Studio MCP tool schemas for maintenance scripts."""

from __future__ import annotations

import json
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))

from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402


WANTED = {"start_stop_play", "get_console_output", "get_studio_state", "execute_luau"}


def main() -> int:
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(3)
        select_studio(client, "BACKROOMS: STAY QUIET [CO-OP HORROR]", 20)
        for tool in client.list_tools():
            if tool.get("name") in WANTED:
                print(json.dumps(tool, ensure_ascii=False, indent=2))
    finally:
        client.close()
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
