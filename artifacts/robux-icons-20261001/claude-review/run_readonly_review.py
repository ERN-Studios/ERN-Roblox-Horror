#!/usr/bin/env python3
"""Bounded, no-tools multimodal Claude review of explicitly supplied images."""

import argparse
import base64
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import signal
import subprocess
import time


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--prompt", required=True, type=Path)
    parser.add_argument("--image", action="append", default=[], type=Path)
    parser.add_argument("--output-prefix", required=True, type=Path)
    parser.add_argument("--wall-seconds", type=int, default=120)
    parser.add_argument("--model", default="claude-opus-5-5")
    parser.add_argument("--effort", default="max", choices=["low", "medium", "high", "xhigh", "max"])
    args = parser.parse_args()
    if not 10 <= args.wall_seconds <= 900:
        parser.error("wall-seconds must be between 10 and 900")

    prompt_path = args.prompt.resolve(strict=True)
    output_prefix = args.output_prefix.resolve()
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    content = [{"type": "text", "text": prompt_path.read_text()}]
    image_manifest = []
    for supplied in args.image:
        path = supplied.resolve(strict=True)
        media_type = mimetypes.guess_type(path.name)[0]
        if media_type not in {"image/png", "image/jpeg", "image/webp", "image/gif"}:
            raise ValueError(f"Unsupported image format: {path.name}")
        raw = path.read_bytes()
        content.append({"type": "text", "text": f"Reference image: {path.name}"})
        content.append({"type": "image", "source": {"type": "base64", "media_type": media_type, "data": base64.b64encode(raw).decode("ascii")}})
        image_manifest.append({"file": str(path), "mediaType": media_type, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})

    request = {"type": "user", "message": {"role": "user", "content": content}}
    command = [
        "/Users/zeanjuul4/.local/bin/claude", "--print", "--safe-mode",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--tools", "", "--permission-mode", "dontAsk",
        "--permission-prompts", "none", "--disable-slash-commands",
        "--no-session-persistence", "--model", args.model,
        "--effort", args.effort, "--input-format", "stream-json",
        "--output-format", "stream-json", "--verbose",
        "--system-prompt", "You are a read-only visual design critic. Inspect only the images and facts supplied by the user. You have no tools and must not infer live application state. Give a concise, concrete critique and design direction within the requested word limit. Do not disclose private internal reasoning.",
    ]
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=output_prefix.parent, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate((json.dumps(request) + "\n").encode(), timeout=args.wall_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    elapsed = round(time.monotonic() - started, 3)
    output_prefix.with_suffix(".stream.jsonl").write_bytes(stdout)
    output_prefix.with_suffix(".stderr.log").write_bytes(stderr)
    events = []
    for line in stdout.decode(errors="replace").splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    init = next((event for event in events if event.get("type") == "system" and event.get("subtype") == "init"), {})
    result = next((event for event in reversed(events) if event.get("type") == "result"), {})
    receipt = {
        "scope": "Read-only review of supplied shop inventory and images; no Studio, file, browser, or MCP tools enabled in Claude",
        "cliPath": command[0], "requestedModel": args.model,
        "reportedCanonicalModel": init.get("model"), "requestedEffort": args.effort,
        "tools": [], "strictEmptyMcpConfig": True, "safeMode": True,
        "inputImages": image_manifest, "elapsedSeconds": elapsed,
        "hardTimeoutSeconds": args.wall_seconds, "exitCode": process.returncode,
        "status": "timeout" if timed_out else ("success" if result and not result.get("is_error") else "error"),
        "isError": result.get("is_error"), "permissionDenials": result.get("permission_denials", []),
        "resultSubtype": result.get("subtype"), "eventCount": len(events),
    }
    output_prefix.with_suffix(".receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if result.get("result"):
        output_prefix.with_suffix(".response.md").write_text(result["result"] + "\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
