"""Check the existing asset importer emits a scoped, no-overwrite V2 installer."""
from pathlib import Path
import importlib.util
import subprocess
import tempfile

ROOT = Path(__file__).resolve().parents[2]


def main():
    spec = importlib.util.spec_from_file_location("level1_import", ROOT / "tools/level1_blender/import_assets.py")
    importer = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(importer)
    with tempfile.TemporaryDirectory() as temporary:
        importer.EXPORT = Path(temporary)
        code = importer.write_installer({"build": "test"}, "Level1BlenderKitV2")
        assert 'not SS:FindFirstChild("Level1BlenderKitV2")' in code
        assert 'kit.Name = "Level1BlenderKitV2"' in code
        assert 'SS:FindFirstChild("Level1BlenderKit")' not in code
        assert 'part.Transparency = style.transparency or 0' in code
        assert 'c.material == "Wallpaper" and Color3.fromRGB' in code
        assert 'kit.Parent = SS' in code and 'if not ok then kit:Destroy(); error(err) end' in code
        compiler = ROOT / "artifacts/hazmat-20260924/luau-0.737/luau-compile.exe"
        subprocess.run([str(compiler), str(importer.EXPORT / "install.luau")], check=True, capture_output=True)
    print("PASS: V2 installer is scoped, no-overwrite, keeps wallpaper tint/glass, and compiles")


if __name__ == "__main__":
    main()
