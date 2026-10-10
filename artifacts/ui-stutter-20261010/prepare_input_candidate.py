"""Prepare an offline UIDevice candidate. Never reads or writes Roblox Studio."""
from pathlib import Path
import argparse
import hashlib

ROOT = Path(__file__).resolve().parents[2]
SOURCE = ROOT / "ReplicatedStorage/UIDevice.ModuleScript.lua"
BEFORE = '''\t-- Last input only affects desktop/gamepad hint SELECTION, never the touch
\t-- decision, but captions still need to be rebuilt when it changes.
\tUserInputService.LastInputTypeChanged:Connect(function()
\t\tif touchFormFactor then return end
\t\tchangedEvent:Fire(UIDevice.Layout())
\tend)'''
AFTER = '''\t-- Mouse and keyboard inputs share one hint layout. Rebuild consumers only
\t-- when their semantic input category changes, rather than on every raw
\t-- mouse/key transition. Real device and layout changes keep their own signals.
\tlocal previousInput = UIDevice.LastInput()
\tlocal previousGamepadEnabled = UserInputService.GamepadEnabled
\tUserInputService.LastInputTypeChanged:Connect(function()
\t\tlocal input = UIDevice.LastInput()
\t\tlocal gamepadEnabled = UserInputService.GamepadEnabled
\t\tif input == previousInput and gamepadEnabled == previousGamepadEnabled then return end
\t\tpreviousGamepadEnabled = gamepadEnabled
\t\tpreviousInput = input
\t\tif touchFormFactor then return end
\t\tchangedEvent:Fire(UIDevice.Layout())
\tend)'''


def candidate(source):
    if source.count(BEFORE) != 1:
        raise ValueError("Input handler changed; reread and reconcile the Studio source")
    return source.replace(BEFORE, AFTER, 1)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--output", type=Path, required=True)
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8")
    result = candidate(source)
    # Exclusive creation preserves other sessions' prepared candidates.
    with args.output.open("x", encoding="utf-8", newline="\n") as handle:
        handle.write(result)
    print("Offline source SHA256:", hashlib.sha256(source.encode()).hexdigest())
    print("Candidate SHA256:", hashlib.sha256(result.encode()).hexdigest())


if __name__ == "__main__":
    main()
