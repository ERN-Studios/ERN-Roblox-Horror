#!/bin/zsh
# Project-scoped launch; inherits existing credentials, MCP and permissions.
set -eu
stayquiet_root="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
stayquiet_effort=medium
if [[ "${1:-}" == --low ]]; then
  stayquiet_effort=low
  shift
fi
cd -- "$stayquiet_root"
# Reserve config/model/cwd flags for this launcher. Use --low for routine work.
# Global options must precede subcommands in the installed Codex CLI.
for stayquiet_arg in "$@"; do
  case "$stayquiet_arg" in
    -C*|--cd|--cd=*|-m*|--model|--model=*|-p*|--profile|--profile=*|-c*|--config|--config=*|--enable|--enable=*|--disable|--disable=*)
      print -u2 -- "Use this project's documented defaults or --low; override flag rejected: $stayquiet_arg"
      exit 2
      ;;
  esac
done
exec /Users/zeanjuul4/.local/bin/codex \
  -C "$stayquiet_root" -m gpt-6.1-sol \
  -c "model_reasoning_effort=\"$stayquiet_effort\"" \
  -c 'service_tier="default"' -c 'agents.enabled=false' "$@"
