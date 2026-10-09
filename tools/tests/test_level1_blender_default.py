"""Level 1 is the Blender world for every round (owner approval 2026-10-04); the developer preview is gone."""

from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
SYSTEMS = ROOT / "ServerScriptService/Level 1 Systems"


def read(path):
    return path.read_text(encoding="utf-8-sig").replace("\r\n", "\n")


def main():
    for folder in ("ServerScriptService", "StarterPlayer", "ReplicatedStorage"):
        for path in (ROOT / folder).rglob("*.lua"):
            if "Archive" in path.parts:
                continue
            assert "Level1BlenderPreview" not in read(path), f"preview reference left in {path.relative_to(ROOT)}"
    for gone in ("ServerScriptService/Level1BlenderPreviewAccess.Script.lua",
                 "StarterPlayer/StarterPlayerScripts/Level1BlenderPreviewButton.LocalScript.lua"):
        assert not (ROOT / gone).exists(), gone

    maze = read(SYSTEMS / "MazeGenerator.Script.lua")
    assert "if roomRenderer.IsReady() then\n\t\tblender = roomRenderer.Begin(maze)\n\telse\n\t\twarn(" in maze, \
        "every Level 1 round builds the Blender world, with the plain maze only as a fallback"

    renderer = read(SYSTEMS / "BlenderRoomRenderer.ModuleScript.lua")
    begin = renderer[renderer.index("function Renderer.Begin(maze)"):]
    begin = begin[:begin.index("local kit = ")]
    assert "GetAttribute(" not in begin, "Begin no longer waits for a preview flag"
    assert 'workspace:SetAttribute("Level1BlenderActive", true)' in begin

    for path in (SYSTEMS / "PuzzleManager.Script.lua", ROOT / "StarterPlayer/StarterPlayerScripts/RoundUI.LocalScript.lua"):
        assert 'GetAttribute("Level1BlenderActive")' in read(path), path.name

    # Every public round runs the Blender cable router now: it must degrade, never abort the puzzle build.
    puzzle = read(SYSTEMS / "PuzzleManager.Script.lua")
    for fatal in ("Preview circuit has no open maze route", 'assert(path, ("Preview cable has no collision-free detour', "Preview cable cell is obstructed"):
        assert fatal not in puzzle, fatal
    assert "pcall(require(script.Parent:WaitForChild(\"BlenderRoomRenderer\")).MakeExitAperture, model, cf)" in puzzle, \
        "a failed exit wall cut must not cost the exit"

    manager = read(ROOT / "ServerScriptService/GameManager.Script.lua")
    assert manager.count('workspace:SetAttribute("Level1BlenderActive", false)') == 2, "boot and round cleanup clear it"
    assert 'local nextLevel = workspace:GetAttribute("Level2BlenderPreviewActive") ~= true and Routing.NextLevel(activeLevel) or nil' in manager, \
        "a Level 1 clear continues to Level 2"
    assert 'if result == "win" and workspace:GetAttribute("Level2BlenderPreviewActive") ~= true then' in manager, \
        "a Level 1 clear is recorded"
    print("Level 1 Blender default: 13 contract checks passed")


if __name__ == "__main__":
    main()
