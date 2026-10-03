"""Create or update the Level 6 playground scripts in the open Studio place.

    python3 tools/level6_playground/push_scripts.py

Each file in studio/ is named "<Name>.<ClassName>.lua"; the parent comes from PARENTS. Existing scripts are
written with ScriptEditorService:UpdateSourceAsync (raw .Source writes leave LocalScripts on stale bytecode),
and their previous source is saved to artifacts/.../studio-before/ the first time.
"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import import_to_studio as studio_io

HERE = Path(__file__).parent
BEFORE = studio_io.ROOT / 'artifacts' / 'level6-playground-20261002' / 'studio-before'
# The Studio MCP sandbox cannot create or reparent scripts, so each new script takes over an obsolete one
# from the retired Level 3 copy (renamed in place; its old source is kept in studio-before/).
TARGETS = {
    'Level 6 Playground Game': ('ServerScriptService.Level 6 Systems', 'Level 6 Preview Runtime'),
    'Level 6 Playground Client': ('StarterPlayer.StarterPlayerScripts', 'Level 6 CD Dev ESP'),
}

PUSH = '''
local parentPath, name, class, reuse, source = %s, %s, %s, %s, [==[%s]==]
local parent = game
for seg in string.gmatch(parentPath, "[^.]+") do parent = parent[seg] end
local scr = parent:FindFirstChild(name)
local before = ""
if not scr then
	scr = parent:FindFirstChild(reuse)
	if not scr then error("neither " .. name .. " nor " .. reuse .. " exists under " .. parentPath) end
	before = "-- " .. reuse .. " (renamed to " .. name .. ")\\n" .. scr.Source
	scr.Name = name
else
	before = scr.Source
end
if not scr:IsA(class) then error(name .. " is a " .. scr.ClassName .. ", expected " .. class) end
game:GetService("ScriptEditorService"):UpdateSourceAsync(scr, function() return source end)
if scr.Source ~= source then error("source readback mismatch for " .. name) end
return before
'''


def main():
    s = studio_io.Studio()
    BEFORE.mkdir(parents=True, exist_ok=True)
    for path in sorted((HERE / 'studio').glob('*.lua')):
        name, cls = path.stem.rsplit('.', 1)
        source = path.read_text()
        if ']==]' in source:
            raise SystemExit(f'{path.name} contains ]==]')
        parent, reuse = TARGETS[name]
        before = s.luau(PUSH % (json.dumps(parent), json.dumps(name), json.dumps(cls), json.dumps(reuse), source))
        keep = BEFORE / path.name
        if before and not keep.exists():
            keep.write_text(before)
        print(f'{name} ({cls}) under {parent}: written, {len(source)} bytes')


if __name__ == '__main__':
    main()
