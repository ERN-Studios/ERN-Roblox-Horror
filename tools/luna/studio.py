"""Run Luau in the open Studio place through the StudioMCP bridge.

    python tools/luna/studio.py [--dm Edit|Server|Client] (-e "<luau>" | file.luau) [--out result.txt]
"""
import argparse
import sys
import time
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from sync_from_studio import StudioMcpClient, find_mcp_batch, select_studio  # noqa: E402

PLACE = "BACKROOMS: STAY QUIET [CO-OP HORROR]"


def run(code: str, dm: str = "Edit") -> str:
    client = StudioMcpClient(find_mcp_batch())
    try:
        client.initialize()
        time.sleep(2)
        studio = select_studio(client, PLACE, 25)
        args = {"datamodel_type": dm, "code": code}
        sid = studio.get("studio_id") or studio.get("id")
        if sid:
            args["studio_id"] = sid
        return client.call("execute_luau", args)
    finally:
        client.close()


if __name__ == "__main__":
    p = argparse.ArgumentParser()
    p.add_argument("file", nargs="?")
    p.add_argument("-e", dest="code")
    p.add_argument("--dm", default="Edit")
    p.add_argument("--out")
    a = p.parse_args()
    code = a.code if a.code is not None else Path(a.file).read_text(encoding="utf-8")
    text = run(code, a.dm)
    if a.out:
        Path(a.out).write_text(text, encoding="utf-8")
    sys.stdout.buffer.write(text.encode("utf-8", "replace") + b"\n")
