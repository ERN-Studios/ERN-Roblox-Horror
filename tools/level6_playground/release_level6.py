"""Open Level 6 (Indoor Playground) to every player; Level 5 stays developer-only.

    python3 tools/level6_playground/release_level6.py

Owner's instruction, 2026-10-03: "release it so it's available in the lobby". Each edit is an exact, counted
text replacement in the Studio script (UpdateSourceAsync); an edit that is already in place is skipped. The
script sources before the change are kept in artifacts/level6-release-20261003/before/.
"""
import json, sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import import_to_studio as studio_io

BEFORE = studio_io.ROOT / 'artifacts' / 'level6-release-20261003' / 'before'
SSS, SPS = 'ServerScriptService', 'StarterPlayer.StarterPlayerScripts'
OLD, NEW = 'DevAccess.IsLevel6PreviewAllowed(player)', 'DevAccess.IsLevel6Allowed(player)'
# (script path, old text, new text, expected count)
EDITS = [
    ('ReplicatedStorage.DevAccess', 'function DevAccess.IsLevel3TimelineOwner(subject)',
     '-- Level 6 (Indoor Playground) is open to every player since 2026-10-03. Level 5 and the developer\n'
     '-- commands still go through the allowlist above.\n'
     'DevAccess.Level6Public = true\n'
     'function DevAccess.IsLevel6Allowed(subject)\n'
     '\treturn DevAccess.Level6Public == true or DevAccess.IsLevel6PreviewAllowed(subject)\n'
     'end\n\n'
     'function DevAccess.IsLevel3TimelineOwner(subject)', 1),
    (SSS + '.GameManager',
     ' if station.revisionOwned and station.level >= 5 and not DevAccess.IsLevel6PreviewAllowed(player) then return false end',
     ' if station.revisionOwned and station.level >= 5\n'
     '  and not (station.level == 6 and DevAccess.IsLevel6Allowed(player) or DevAccess.IsLevel6PreviewAllowed(player)) then return false end', 1),
    (SSS + '.GameManager', ' return "DEV PARTY QUEUE  •  AUTHORIZED ACCESS"\nend',
     ' if station.level == 6 then return "HIDE AND SEEK  •  1-6 PLAYERS" end\n return "DEV PARTY QUEUE  •  AUTHORIZED ACCESS"\nend', 1),
    (SSS + '.Level6PreviewAccess', OLD, NEW, 2),
    (SSS + '.LobbyReimaginedPreview.DevBayAccessGuard', '\t\t\t\tlocal inside, gate = insideProtectedBay(record, root.Position)',
     '\t\t\t\tif record.level == 6 and DevAccess.IsLevel6Allowed(player) then continue end   -- Level 6 is public\n'
     '\t\t\t\tlocal inside, gate = insideProtectedBay(record, root.Position)', 1),
    (SPS + '.R4DevGateController', '\tlocal predicate = access.IsLevel6PreviewAllowed',
     '\tlocal predicate = level == 6 and access.IsLevel6Allowed or access.IsLevel6PreviewAllowed   -- Level 6 is public', 1),
    (SPS + '.Level6PreviewTransport', 'if not DevAccess.IsLevel6PreviewAllowed(player) then return end',
     'if not DevAccess.IsLevel6Allowed(player) then return end', 1),
    (SPS + '.Level4PreviewPrompt', '\tLevel6DeveloperPreviewPrompt = true,\n\tLevel6DeveloperPreviewReturnPrompt = true,\n',
     '\t-- Level 6 is public since 2026-10-03: its prompts are no longer hidden\n', 1),
]
PATCH = '''
local path, old, new, expected = %s, %s, %s, %d
local scr = game
for seg in string.gmatch(path, "[^.]+") do scr = scr[seg] end
local src = scr.Source
local function count(hay, needle)
	local n, at = 0, 1
	while true do
		local a, b = string.find(hay, needle, at, true)
		if not a then return n end
		n += 1; at = b + 1
	end
end
if count(src, new) >= expected and count(src, old) == (string.find(new, old, 1, true) and expected or 0) then return "already applied" end
local found = count(src, old)
if found ~= expected then error(path .. ": expected " .. expected .. " of the old text, found " .. found) end
local out, at = {}, 1
while true do
	local a, b = string.find(src, old, at, true)
	if not a then out[#out + 1] = string.sub(src, at); break end
	out[#out + 1] = string.sub(src, at, a - 1); out[#out + 1] = new; at = b + 1
end
local result = table.concat(out)
game:GetService("ScriptEditorService"):UpdateSourceAsync(scr, function() return result end)
if scr.Source ~= result then error("readback mismatch for " .. path) end
return "patched (" .. #src .. " -> " .. #result .. " chars)"
'''
READ = 'local scr = game\nfor seg in string.gmatch(%s, "[^.]+") do scr = scr[seg] end\nreturn scr.Source'


def main():
    s = studio_io.Studio()
    BEFORE.mkdir(parents=True, exist_ok=True)
    for path, old, new, expected in EDITS:
        keep = BEFORE / (path + '.lua')
        if not keep.exists():
            keep.write_text(s.luau(READ % json.dumps(path)))
        print(path.split('.')[-1], '->', s.luau(PATCH % (json.dumps(path), json.dumps(old, ensure_ascii=False), json.dumps(new, ensure_ascii=False), expected)))


if __name__ == '__main__':
    main()
