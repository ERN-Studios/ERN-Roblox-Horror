"""Run a .luau file in the open Studio place and print what it returns.

    python3 tools/level6_playground/run_luau.py <file.luau> [Edit|Server|Client]
"""
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))
from import_to_studio import Studio   # noqa: E402

studio = Studio()
print(studio.call('execute_luau', {'studio_id': studio.studio_id, 'datamodel_type': sys.argv[2] if len(sys.argv) > 2 else 'Edit',
                                    'code': Path(sys.argv[1]).read_text()}))
