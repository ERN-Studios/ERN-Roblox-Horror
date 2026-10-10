#!/bin/zsh
# Project-scoped launch; inherits existing credentials, MCP and permissions.
set -eu
stayquiet_root="$(cd -- "$(dirname -- "$0")/../.." && pwd -P)"
# Owner, 2026-10-10 (evening): High is the main agent's default; --medium for clearly bounded routine work.
stayquiet_effort=high
if [[ "${1:-}" == --medium ]]; then
  stayquiet_effort=medium
  shift
fi
cd -- "$stayquiet_root"
exec /Users/zeanjuul4/.local/bin/claude "$@" --model opus \
  --effort "$stayquiet_effort" \
  --settings "{\"effortLevel\":\"$stayquiet_effort\",\"fastMode\":false,\"ultracode\":false}"
