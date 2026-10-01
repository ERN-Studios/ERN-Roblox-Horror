#!/usr/bin/env python3
"""Bounded Claude critique of explicitly supplied lobby facts and image bytes."""

import argparse
import base64
from datetime import datetime, timezone
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
    parser.add_argument("--wall-seconds", type=int, default=600)
    parser.add_argument("--model", default="claude-opus-5-5")
    parser.add_argument("--effort", default="max", choices=["low", "medium", "high", "xhigh", "max"])
    args = parser.parse_args()
    if not 10 <= args.wall_seconds <= 900:
        parser.error("wall-seconds must be between 10 and 900")
    prompt_path = args.prompt.resolve(strict=True)
    output_prefix = args.output_prefix.resolve()
    output_prefix.parent.mkdir(parents=True, exist_ok=True)
    prompt_bytes = prompt_path.read_bytes()
    content = [{"type": "text", "text": prompt_bytes.decode()}]
    images = []
    for supplied in args.image:
        path = supplied.resolve(strict=True)
        media_type = mimetypes.guess_type(path.name)[0]
        if media_type not in {"image/png", "image/jpeg", "image/webp", "image/gif"}:
            raise ValueError(f"Unsupported image format: {path.name}")
        raw = path.read_bytes()
        content.append({"type": "text", "text": f"Fresh supplied reference: {path.name}"})
        content.append({"type": "image", "source": {"type": "base64", "media_type": media_type, "data": base64.b64encode(raw).decode("ascii")}})
        images.append({"file": str(path), "mediaType": media_type, "bytes": len(raw), "sha256": hashlib.sha256(raw).hexdigest()})
    command = [
        "/Users/zeanjuul4/.local/bin/claude", "--print", "--safe-mode",
        "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}',
        "--tools", "", "--permission-mode", "dontAsk", "--permission-prompts", "none",
        "--disable-slash-commands", "--no-session-persistence", "--model", args.model,
        "--effort", args.effort, "--input-format", "stream-json",
        "--output-format", "stream-json", "--verbose", "--system-prompt",
        "You are a read-only architectural and game-environment design critic. Use only supplied facts and images. You have no tools and cannot inspect or mutate live applications. Distinguish visual observations from proposals. Respect the user's existing style and gameplay. Give concrete, concise advice within the requested word limit. Do not disclose private internal reasoning.",
    ]
    began_at = datetime.now(timezone.utc).isoformat()
    started = time.monotonic()
    process = subprocess.Popen(command, cwd=output_prefix.parent, stdin=subprocess.PIPE, stdout=subprocess.PIPE, stderr=subprocess.PIPE, start_new_session=True)
    timed_out = False
    try:
        stdout, stderr = process.communicate((json.dumps({"type": "user", "message": {"role": "user", "content": content}}) + "\n").encode(), timeout=args.wall_seconds)
    except subprocess.TimeoutExpired:
        timed_out = True
        os.killpg(process.pid, signal.SIGTERM)
        try:
            stdout, stderr = process.communicate(timeout=5)
        except subprocess.TimeoutExpired:
            os.killpg(process.pid, signal.SIGKILL)
            stdout, stderr = process.communicate()
    events = []
    for line in stdout.decode(errors="replace").splitlines():
        try:
            events.append(json.loads(line))
        except json.JSONDecodeError:
            pass
    init = next((e for e in events if e.get("type") == "system" and e.get("subtype") == "init"), {})
    result = next((e for e in reversed(events) if e.get("type") == "result"), {})
    visible_assistant_text = []
    for event in events:
        if event.get("type") != "assistant":
            continue
        for block in event.get("message", {}).get("content", []):
            if block.get("type") == "text" and block.get("text"):
                visible_assistant_text.append(block["text"])
    receipt = {
        "scope": "Read-only critique of supplied lobby observations/images; no tools or live application access",
        "startedAtUTC": began_at, "finishedAtUTC": datetime.now(timezone.utc).isoformat(),
        "cliPath": command[0], "requestedModel": args.model,
        "reportedCanonicalModel": init.get("model"), "requestedEffort": args.effort,
        "highestEffortSupportedByInspectedCLIHelp": "max",
        "reportedTools": init.get("tools"), "strictEmptyMcpConfig": True, "safeMode": True,
        "inputPrompt": str(prompt_path), "inputPromptSHA256": hashlib.sha256(prompt_bytes).hexdigest(),
        "inputImages": images, "elapsedSeconds": round(time.monotonic() - started, 3),
        "hardTimeoutSeconds": args.wall_seconds, "exitCode": process.returncode,
        "status": "timeout" if timed_out else ("success" if result and not result.get("is_error") else "error"),
        "isError": result.get("is_error"), "permissionDenials": result.get("permission_denials", []),
        "resultSubtype": result.get("subtype"), "eventCount": len(events),
        "rawInternalStreamSaved": False,
        "visibleAssistantTextBlocks": len(visible_assistant_text),
        "eventTypeCounts": {
            kind: sum(e.get("type") == kind for e in events)
            for kind in sorted({str(e.get("type")) for e in events})
        },
    }
    output_prefix.with_suffix(".receipt.json").write_text(json.dumps(receipt, indent=2) + "\n")
    if result.get("result"):
        output_prefix.with_suffix(".response.md").write_text(result["result"] + "\n")
    elif visible_assistant_text:
        # Preserve only user-visible text, never private thinking/reasoning blocks.
        output_prefix.with_suffix(".partial-visible-response.md").write_text(
            "Incomplete CLI run: no final result event; visible assistant text only.\n\n"
            + "\n\n".join(visible_assistant_text) + "\n"
        )
    if stderr:
        output_prefix.with_suffix(".stderr.log").write_bytes(stderr)
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
