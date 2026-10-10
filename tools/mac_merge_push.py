"""Repo -> Studio on the Mac for scripts ANOTHER SESSION may have edited in Studio since the pull: three-way merge the
working copy with what Studio holds NOW, write the result into Studio (Edit) and read it back whole.

    python3 tools/mac_merge_push.py [--dry] "<repo-relative file>" ...

tools/mac_push_script.py refuses when Studio has drifted; this merges instead. Push clients before the servers they talk to.

base   = git HEAD:<file>   (the mirror as last pulled / committed)
mine   = the working file  (this batch's edit)
theirs = Studio's current source (another session may have edited it since the pull)

Studio == base            -> write mine
Studio == mine            -> nothing to do
otherwise                 -> git merge-file (mine, base, theirs); a conflict stops that file, nothing is written.
The write is a compare-and-swap inside UpdateSourceAsync (length + checksum of what was merged against), the result is
fetched back whole and compared byte for byte, and the working file is replaced by the merged text so repo == Studio.
"""
import hashlib, json, os, shutil, subprocess, sys, tempfile
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
LUAU_COMPILE = os.environ.get('LUAU_COMPILE_BIN') or shutil.which('luau-compile')   # optional: the merged text is compiled first
# The text this checkout last wrote into Studio, per file. It is the merge base from then on: after a first push the
# committed HEAD is no longer what Studio holds, and merging against it would conflict with our own earlier push.
PUSHED = Path(tempfile.gettempdir()) / ('stayquiet-pushed-' + hashlib.sha1(str(ROOT).encode()).hexdigest()[:10])
sys.path.insert(0, str(ROOT / 'tools' / 'level6_playground'))
import import_to_studio as studio_io  # noqa: E402

FIND = 'local n = game\nfor _, seg in ipairs(game:GetService("HttpService"):JSONDecode(%s)) do n = n:FindFirstChild(seg) end\n'
SIG = '''
local function sig(v)
	local sum, roll = 0, 0
	for i = 1, #v do local ch = string.byte(v, i); sum += ch; roll = (roll * 31 + ch) % 4294967291 end
	return #v .. ":" .. sum .. ":" .. roll
end
'''


def sig(b: bytes) -> str:
    roll = 0
    for ch in b:
        roll = (roll * 31 + ch) % 4294967291
    return f'{len(b)}:{sum(b)}:{roll}'


def path_of(rel):
    parts = list(Path(rel).parts)
    return parts[:-1] + [parts[-1].rsplit('.', 2)[0]]


def fetch(s, rel) -> bytes:
    find = FIND % json.dumps(json.dumps(path_of(rel)))
    size = int(s.luau(find + 'assert(n and n:IsA("LuaSourceContainer"), "missing script")\nreturn tostring(#n.Source)'))
    out, at = [], 1
    while at <= size:
        # cut on a UTF-8 boundary so no chunk ends inside a character
        chunk = s.luau(find + '''
local src, at = n.Source, %d
local stop = math.min(#src, at + 59999)
while stop < #src do
	local b = string.byte(src, stop + 1)
	if b >= 128 and b < 192 then stop -= 1 else break end
end
return tostring(stop) .. "|" .. string.sub(src, at, stop)''' % at)
        stop, text = chunk.split('|', 1)
        out.append(text)
        at = int(stop) + 1
    data = ''.join(out).encode()
    assert len(data) == size, f'{rel}: fetched {len(data)} bytes, Studio says {size}'
    return data


def write(s, rel, expect: bytes, new: bytes):
    text = new.decode()
    level = '=='
    while (']' + level + ']') in text:
        level += '='
    # A long string drops ONE leading newline; add one so the payload arrives intact.
    code = (FIND % json.dumps(json.dumps(path_of(rel)))) + SIG + '''
local new = [%s[
%s]%s]
assert(sig(new) == %s, "payload was altered in transport: " .. sig(new))
assert(not game:GetService("RunService"):IsRunning(), "Edit only")
game:GetService("ScriptEditorService"):UpdateSourceAsync(n, function(current)
	assert(sig(current) == %s, "Studio changed since the merge: " .. sig(current))
	return new
end)
assert(n.Source == new, "readback mismatch")
return "written " .. sig(n.Source)
''' % (level, text, level, json.dumps(sig(new)), json.dumps(sig(expect)))
    return s.luau(code)


def main():
    dry = '--dry' in sys.argv
    rels = [a for a in sys.argv[1:] if not a.startswith('--')]
    s = studio_io.Studio()
    failed = 0
    for rel in rels:
        f = ROOT / rel
        mine = f.read_bytes()
        stored = PUSHED / rel
        base = stored.read_bytes() if stored.exists() else subprocess.run(['git', 'show', f'HEAD:{rel}'], cwd=ROOT, capture_output=True).stdout
        theirs = fetch(s, rel)
        if theirs == mine:
            print(f'{rel}: Studio already holds the working copy ({sig(mine)})')
            (PUSHED / rel).parent.mkdir(parents=True, exist_ok=True)
            (PUSHED / rel).write_bytes(mine)
            continue
        if theirs == base:
            merged, how = mine, 'studio == base'
        else:
            with tempfile.TemporaryDirectory() as d:
                a, b, c = Path(d, 'mine'), Path(d, 'base'), Path(d, 'theirs')
                a.write_bytes(mine); b.write_bytes(base); c.write_bytes(theirs)
                r = subprocess.run(['git', 'merge-file', '-p', '-L', 'mine', '-L', 'base', '-L', 'studio', str(a), str(b), str(c)],
                                   capture_output=True)
            if r.returncode != 0:
                print(f'{rel}: MERGE CONFLICT ({r.returncode}) between this batch and another session\'s Studio edit; nothing written')
                Path(tempfile.gettempdir(), 'conflict_' + Path(rel).name).write_bytes(r.stdout)
                failed += 1
                continue
            merged, how = r.stdout, f'merged with a Studio edit ({len(base)} -> {len(theirs)} bytes there)'
        with tempfile.NamedTemporaryFile(suffix='.lua', delete=False) as t:
            t.write(merged)
        c = subprocess.run([LUAU_COMPILE, t.name], capture_output=True, text=True) if LUAU_COMPILE else None
        if c is not None and c.returncode != 0:
            print(f'{rel}: merged text does NOT compile: {c.stderr.strip()[:300] or c.stdout.strip()[:300]}')
            failed += 1
            continue
        if dry:
            print(f'{rel}: would write {sig(merged)} ({how})')
            continue
        print(f'{rel}: {write(s, rel, theirs, merged)} ({how})')
        back = fetch(s, rel)
        assert back == merged, f'{rel}: Studio holds {sig(back)}, expected {sig(merged)}'
        (PUSHED / rel).parent.mkdir(parents=True, exist_ok=True)
        (PUSHED / rel).write_bytes(merged)
        if merged != mine:
            f.write_bytes(merged)
    if failed:
        raise SystemExit(f'{failed} file(s) not written')


if __name__ == '__main__':
    main()
