"""Install the Level 1 Entity's motion layer into the open Studio place (Edit mode).

    python3 tools/level1_entity/install_motion.py <clips.json>

Writes the six clips as StringValues under ReplicatedStorage.Level1EntityMotion.Clips (one clip per value, compact
JSON, the layout the LocalScript "Level 1 Entity Motion" reads) and creates that LocalScript in StarterPlayerScripts
from the mirrored file when the place does not have it yet. Re-runnable: values are replaced, an existing script is
left to tools/mac_push_script.py. Every value is read back and compared by length and checksum.
"""
import json, sys
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io  # noqa: E402

SCRIPT = ROOT / 'StarterPlayer' / 'StarterPlayerScripts' / 'Level 1 Entity Motion.LocalScript.lua'
SIG = '''
local function sig(v)
	local sum, roll = 0, 0
	for i = 1, #v do local ch = string.byte(v, i); sum += ch; roll = (roll * 31 + ch) % 4294967291 end
	return #v .. ":" .. sum .. ":" .. roll
end
'''


def sig(text):
    b = text.encode(); roll = 0
    for ch in b:
        roll = (roll * 31 + ch) % 4294967291
    return f'{len(b)}:{sum(b)}:{roll}'


def main():
    clips = json.loads(Path(sys.argv[1]).read_text())
    s = studio_io.Studio()
    print(s.luau('''
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
local RS = game:GetService("ReplicatedStorage")
local root = RS:FindFirstChild("Level1EntityMotion") or Instance.new("Folder")
root.Name = "Level1EntityMotion"
root:SetAttribute("Revision", "ENTITY_MOTION_20261010")
local clips = root:FindFirstChild("Clips") or Instance.new("Folder")
clips.Name, clips.Parent = "Clips", root
root.Parent = RS
return "folder ready: " .. root:GetFullName()
'''))
    for name, clip in clips.items():
        text = json.dumps(clip, separators=(',', ':'))
        assert ']==]' not in text and len(text) < 190000, name
        print(name, s.luau(SIG + '''
local clips = game:GetService("ReplicatedStorage").Level1EntityMotion.Clips
local value = [==[%s]==]
assert(sig(value) == %s, "payload altered in transport")
local v = clips:FindFirstChild(%s) or Instance.new("StringValue")
v.Name, v.Value, v.Parent = %s, value, clips
assert(v.Value == value, "readback")
local decoded = game:GetService("HttpService"):JSONDecode(v.Value)
local bones = 0
for _ in pairs(decoded.bones) do bones += 1 end
return string.format("%%d chars, %%d frames at %%.2f fps, %%d bone tracks, loop=%%s", #v.Value, decoded.frames, decoded.fps, bones, tostring(decoded.loop))
''' % (text, json.dumps(sig(text)), json.dumps(name), json.dumps(name))))
    source = SCRIPT.read_text()
    assert ']==]' not in source
    print('script:', s.luau(SIG + '''
local scripts = game:GetService("StarterPlayer").StarterPlayerScripts
local existing = scripts:FindFirstChild("Level 1 Entity Motion")
if existing then return "already there (" .. sig(existing.Source) .. "); push changes with the push tool" end
local source = [==[
%s]==]
assert(sig(source) == %s, "payload altered in transport")
local script = Instance.new("LocalScript")
script.Name = "Level 1 Entity Motion"
script.Parent = scripts
game:GetService("ScriptEditorService"):UpdateSourceAsync(script, function() return source end)
assert(script.Source == source, "readback")
return "created " .. script:GetFullName() .. " " .. sig(script.Source)
''' % (source, json.dumps(sig(source)))))


main()
