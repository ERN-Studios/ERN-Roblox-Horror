"""Retired Studio entity-animation export entrypoint."""
from __future__ import annotations

# Exact prior sources remain in the S25/S25b cleanup archives.
RETIRED_WORKFLOW_MESSAGE = 'Retired Studio entity-animation authoring workflow. Published gameplay IDs, versioned receipts and regeneration inputs are retained. This entrypoint performs no upload or Studio operation.'
if __name__ == '__main__':
    raise SystemExit(RETIRED_WORKFLOW_MESSAGE)
raise RuntimeError(RETIRED_WORKFLOW_MESSAGE)
