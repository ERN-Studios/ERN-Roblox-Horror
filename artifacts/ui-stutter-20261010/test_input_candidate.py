"""Offline real-UIDevice input event regression and existing full equipment QA.

Synthetic collaborators establish event behavior, not measured Roblox frame time.
No Studio connection, native state writes or network calls.
"""
from pathlib import Path
import argparse
import contextlib
import hashlib
import io
import json
import subprocess
import sys
import tempfile

from prepare_input_candidate import AFTER, BEFORE, SOURCE, ROOT, candidate

sys.path.insert(0, str(ROOT / "tools/tests"))
import test_equipment_hud as equipment

CONTEXT_ANCHOR = "\tfunction ctx.UserInputService:GetFocusedTextBox() return ctx.FocusedTextBox end"
CONTEXT_EXTRA = '''\tfunction ctx.UserInputService:GetLastInputType()
\t\treturn ctx.LastInput or Enum.UserInputType.Keyboard
\tend
'''

TESTS = r'''
local ctx = makeContext()
ctx.NoSpawn = true
ctx.UserInputService.GamepadEnabled = true
local device = bootModule(ctx, UIDeviceSource)
local changed = 0
device.Changed:Connect(function() changed += 1 end)
local function input(name)
    ctx.LastInput = Enum.UserInputType[name]
    ctx.UserInputService.LastInputTypeChanged:Fire(ctx.LastInput)
end
for _ = 1, 20 do
    for _, name in ipairs({"MouseMovement", "Keyboard", "MouseButton1", "MouseButton2", "MouseWheel"}) do input(name) end
end
check(changed == 0, "100 keyboard/mouse events must not rebuild the hint layout")
check(device.LastInput() == "Keyboard" and device.Binding("[Q]", "[RT]") == "[Q]", "pointer hints remain keyboard hints")
input("Gamepad1")
check(changed == 1 and device.Binding("[Q]", "[RT]") == "[RT]", "gamepad category refreshes immediately")
input("Gamepad2")
check(changed == 1, "switching gamepad subtype keeps its hint category")
input("Keyboard")
check(changed == 2 and device.Binding("[Q]", "[RT]") == "[Q]", "returning to keyboard refreshes immediately")
input("Touch")
check(changed == 3 and device.LastInput() == "Touch", "touch input on a pointer form remains a distinct category")
input("Keyboard")
check(changed == 4, "return from pointer-form touch is delivered")
input("Gamepad1")
ctx.workspace:SetAttribute("ForceTouchUI", true)
local atTouch = changed
input("Keyboard")
input("MouseMovement")
check(changed == atTouch, "handheld form suppresses input-only rebuilds")
check(device.Binding("[Q]", "[RT]") == "", "handheld still suppresses keyboard and gamepad glyphs")
ctx.workspace:SetAttribute("ForceTouchUI", false)
local atPointer = changed
input("Keyboard")
check(changed == atPointer, "normalized cache advances while handheld input-only events are suppressed")
check(device.Binding("[Q]", "[RT]") == "[Q]", "hardware form flip restores current pointer hint")
input("Gamepad1")
local beforeDisconnect = changed
ctx.UserInputService.GamepadEnabled = false
input("Gamepad2")
check(changed == beforeDisconnect + 1 and device.Binding("[Q]", "[RT]") == "[Q]", "same-category event after controller disconnect restores keyboard glyph")
ctx.UserInputService.GamepadEnabled = true
input("Gamepad1")
check(changed == beforeDisconnect + 2 and device.Binding("[Q]", "[RT]") == "[RT]", "same-category event after controller reconnect restores gamepad glyph")
input("Keyboard")
local beforeViewport = changed
ctx.camera.ViewportSize = Vector2.new(1440, 900)
ctx.camera:GetPropertyChangedSignal("ViewportSize"):Fire()
check(changed > beforeViewport, "actual viewport resize still notifies consumers")
local beforeHardware = changed
ctx.UserInputService.MouseEnabled = false
ctx.UserInputService:GetPropertyChangedSignal("MouseEnabled"):Fire()
check(changed > beforeHardware, "hardware change still forces refresh")
local beforeModal = changed
ctx.player:SetAttribute("QueueModalOpen", true)
check(changed > beforeModal, "modal layout change remains an immediate notification")
print("UIDevice input event contract: " .. checks .. " checks passed")
'''


def run(binary, program, path):
    path.write_text(program, encoding="utf-8", newline="\n")
    return subprocess.run([str(binary), str(path)], capture_output=True, text=True, timeout=60)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--source", type=Path, default=SOURCE)
    parser.add_argument("--luau", type=Path, default=ROOT / "artifacts/hazmat-20260924/luau-0.737/luau.exe")
    parser.add_argument("--receipt", type=Path)
    args = parser.parse_args()
    source = args.source.read_text(encoding="utf-8")
    # Also exercise the real module after the verified candidate is installed.
    # Reconstruct only the raw-event mutant; never modify the source mirror.
    if source.count(AFTER) == 1 and BEFORE not in source:
        proposed = source
        raw_broadcasting = source.replace(AFTER, BEFORE, 1)
    else:
        proposed = candidate(source)
        raw_broadcasting = source
    if equipment.CONTEXT.count(CONTEXT_ANCHOR) != 1:
        raise ValueError("Equipment fake input service changed")
    fake_context = equipment.CONTEXT.replace(CONTEXT_ANCHOR, CONTEXT_EXTRA + CONTEXT_ANCHOR, 1)
    def program(value):
        return equipment.ENGINE + fake_context + equipment.BOOTS + equipment.wrap("UIDeviceSource", value) + TESTS
    with tempfile.TemporaryDirectory(prefix="ui-input-offline-") as temporary:
        folder = Path(temporary)
        path = folder / "UIDevice.candidate.luau"
        path.write_text(proposed, encoding="utf-8", newline="\n")
        compiler = args.luau.with_name("luau-compile.exe")
        subprocess.run([str(compiler), "--null", str(path)], capture_output=True, check=True)
        result = run(args.luau, program(proposed), folder / "input-contract.luau")
        if result.returncode:
            raise RuntimeError(result.stdout + result.stderr)
        mutations = {
            "original raw input broadcasting": raw_broadcasting,
            "gamepad notifications removed": proposed.replace("\t\tchangedEvent:Fire(UIDevice.Layout())", "\t\t-- missing hint notification", 1),
            "cache not updated during handheld input": proposed.replace("\t\tpreviousInput = input\n\t\tif touchFormFactor then return end", "\t\tif touchFormFactor then return end\n\t\tpreviousInput = input", 1),
            "controller availability omitted from hint cache": proposed.replace("input == previousInput and gamepadEnabled == previousGamepadEnabled", "input == previousInput", 1),
        }
        for name, changed in mutations.items():
            if run(args.luau, program(changed), folder / "mutation.luau").returncode == 0:
                raise AssertionError("Test accepted mutation: " + name)
        # Run all existing real-template equipment/control-plan checks with only
        # the fake engine's newly used GetLastInputType API supplied.
        original_device, original_context = equipment.UIDEVICE, equipment.CONTEXT
        import os
        original_binary = os.environ.get("LUAU_BIN")
        try:
            equipment.UIDEVICE, equipment.CONTEXT = path, fake_context
            os.environ["LUAU_BIN"] = str(args.luau.resolve())
            output = io.StringIO()
            with contextlib.redirect_stdout(output):
                equipment.main()
        finally:
            equipment.UIDEVICE, equipment.CONTEXT = original_device, original_context
            if original_binary is None: os.environ.pop("LUAU_BIN", None)
            else: os.environ["LUAU_BIN"] = original_binary
    receipt = {
        "source": str(args.source.resolve().relative_to(ROOT)).replace("\\", "/")
                  if args.source.resolve().is_relative_to(ROOT) else args.source.name,
        "sourceSHA256": hashlib.sha256(source.encode()).hexdigest(),
        "candidateSHA256": hashlib.sha256(proposed.encode()).hexdigest(),
        "candidateCompiled": True,
        "inputContract": result.stdout.strip(), "mutationsRejected": list(mutations),
        "equipmentContract": output.getvalue().strip(),
        "studioModified": False, "nativeFrameTimeMeasured": False,
        "scope": "Offline actual-source event behavior and equipment/control-plan contract",
    }
    if args.receipt:
        args.receipt.write_text(json.dumps(receipt, indent=2) + "\n", encoding="utf-8", newline="\n")
    print(json.dumps(receipt, indent=2))


if __name__ == "__main__":
    main()
