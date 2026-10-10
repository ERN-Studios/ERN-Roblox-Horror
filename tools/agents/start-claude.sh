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
exec /Users/zeanjuul4/.local/bin/claude "$@" --model opus \
  --effort "$stayquiet_effort" \
  --settings "{\"effortLevel\":\"$stayquiet_effort\",\"fastMode\":false,\"ultracode\":false}"
