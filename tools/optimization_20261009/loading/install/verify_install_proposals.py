"""Run the frozen contracts against proposals reconciled to fresh Edit exports."""
import importlib.util
import json
from pathlib import Path
import sys

HERE = Path(__file__).resolve().parent
PARENT = HERE.parent

def load(name, path):
    spec = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module

def main():
    if len(sys.argv) != 2:
        raise SystemExit("Pass the official Luau executable path.")
    binary = sys.argv[1]
    loading = load("install_loading_policy", PARENT / "test_loading_policy.py")
    loading.HERE = HERE
    loading.BEFORE = HERE / "LobbyLoading.before.luau"
    loading.PROPOSED = HERE / "LobbyLoading.proposed.luau"
    sys.argv = ["test_loading_policy.py", "--luau", binary, "--emit-native",
        str(HERE / "native-loading-contract-probe.luau")]
    loading.main()
    loading_result = json.loads((HERE / "offline-result.json").read_text())
    (HERE / "loading-offline-result.json").write_text(json.dumps(loading_result, indent=2)+"\n", encoding="utf-8")
    spectator = load("install_spectate_focus", PARENT / "spectate" / "test_spectate_focus.py")
    spectator.HERE = HERE
    sys.argv = ["test_spectate_focus.py", "--luau", binary, "--emit-native",
        str(HERE / "native-spectate-contract-probe.luau")]
    spectator.main()
    spectate_result = json.loads((HERE / "offline-result.json").read_text())
    (HERE / "spectate-offline-result.json").write_text(json.dumps(spectate_result, indent=2)+"\n", encoding="utf-8")
    (HERE / "offline-result.json").unlink()
    assert loading_result["source_sha256"] == json.loads((PARENT / "offline-result.json").read_text())["source_sha256"]
    assert spectate_result["source_sha256"] == json.loads((PARENT / "spectate" / "offline-result.json").read_text())["source_sha256"]

if __name__ == "__main__":
    main()
