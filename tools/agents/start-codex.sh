#!/bin/zsh
# Project-scoped launch; inherits existing credentials, MCP and permissions.
set -eu
stayquiet_root="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
# Owner, 2026-10-10 (evening): Medium by default; --high for hard debugging, client/server interplay or a
# risky review; --low for simple known procedures. Never ultra/xhigh, never the priority (Fast) tier.
stayquiet_effort=medium
case "${1:-}" in
  --low) stayquiet_effort=low; shift ;;
  --high) stayquiet_effort=high; shift ;;
esac
cd -- "$stayquiet_root"
# Reserve config/model/cwd flags for this launcher.
# Global options must precede subcommands in the installed Codex CLI.
for stayquiet_arg in "$@"; do
  case "$stayquiet_arg" in
    -C*|--cd|--cd=*|-m*|--model|--model=*|-p*|--profile|--profile=*|-c*|--config|--config=*|--enable|--enable=*|--disable|--disable=*)
      print -u2 -- "Use this project's documented defaults, --high or --low; override flag rejected: $stayquiet_arg"
      exit 2
      ;;
  esac
done
exec /Users/zeanjuul4/.local/bin/codex \
  -C "$stayquiet_root" -m gpt-6.1-sol \
  -c "model_reasoning_effort=\"$stayquiet_effort\"" \
  -c 'service_tier="default"' -c 'agents.enabled=false' "$@"
